"""本計算：模擬 Wafer を作り、Shot 数ごとのサンプリング計画で全手法を当てはめ、推定精度を記録する。

使い方
    python -m src.simulation --config config/default.json
    python -m src.simulation --config config/default.json --n-wafers 20 --results-dir results_smoke

- Wafer は wafers_per_chunk 枚ずつのまとまり（chunk）に分けて並列に計算し、chunk ごとに CSV（gzip）へ書き出す。
  途中で止まっても、再実行すると書き出し済みの chunk を飛ばして続きから計算する。
- 全 chunk が終わると results/tables/per_wafer_metrics.csv.gz にまとめる。
- 図や表の作成は src.summarize と src.plotting で行う。
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import platform
import sys
import time
from pathlib import Path

# 並列計算の各プロセスで線形代数ライブラリがさらにスレッドを作らないようにする（子プロセスにも引き継がれる）
for _name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_name, "1")

import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

from .geometry import WaferLayout, build_layout  # noqa: E402
from .methods import LevelContext, MethodSpec, build_method_specs  # noqa: E402
from .metrics import wafer_metrics  # noqa: E402
from .sampling import SamplingPlan, constrained_i_optimal, train_mark_mask  # noqa: E402
from .wafer_generator import GenerationSettings, WaferGenerator  # noqa: E402

PLAN_STREAM = 999
SAMPLE_WAFERS = (0, 1, 2)
PLAN_CACHE_DIR = Path(".cache")


def load_config(path: str | Path) -> dict:
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _plan_cache_path(config: dict) -> Path:
    """計画は配置・サンプリング設定・乱数の種だけで決まるので、その内容のハッシュをファイル名にする。"""
    key = json.dumps({k: config[k] for k in ("wafer", "shot", "sampling")} | {"seed": config["random"]["master_seed"]}, sort_keys=True)
    return PLAN_CACHE_DIR / f"sampling_plans_{hashlib.sha256(key.encode()).hexdigest()[:16]}.json"


def build_plans(layout: WaferLayout, config: dict) -> list[SamplingPlan]:
    """Shot 数ごとの制約付き I 最適計画（全 Wafer 共通）。同じ設定で計算済みならキャッシュから読む。"""
    sampling = config["sampling"]
    if sampling.get("criterion", "I") != "I":
        raise ValueError("サンプリングの基準は I 最適のみ対応")
    cache = _plan_cache_path(config)
    if cache.exists():
        with open(cache, encoding="utf-8") as handle:
            records = json.load(handle)
        return [SamplingPlan(r["n_shots"], np.array(r["shot_indices"]), r["criterion_value"], r["feasible"]) for r in records]
    seed = int(config["random"]["master_seed"])
    plans = []
    for n_shots in sampling["n_shots"]:
        rng = np.random.default_rng([seed, PLAN_STREAM, int(n_shots)])
        plan = constrained_i_optimal(
            layout,
            int(n_shots),
            int(sampling["design_xy_order"]),
            sampling["constraints"],
            rng,
            n_starts=int(sampling["exchange_starts"]),
            max_iterations=int(sampling["exchange_max_iterations"]),
        )
        if not plan.feasible:
            raise RuntimeError(f"{n_shots} Shot の計画が制約を満たさない")
        plans.append(plan)
    PLAN_CACHE_DIR.mkdir(exist_ok=True)
    records = [
        {"n_shots": p.n_shots, "shot_indices": p.shot_indices.tolist(), "criterion_value": p.criterion_value, "feasible": p.feasible}
        for p in plans
    ]
    with open(cache, "w", encoding="utf-8") as handle:
        json.dump(records, handle)
    return plans


# ---- 並列計算の各プロセスで1回だけ作る状態
_WORKER: dict = {}


def _init_worker(config: dict, plans: list[SamplingPlan]) -> None:
    layout = build_layout(config)
    specs = build_method_specs(config)
    _WORKER["config"] = config
    _WORKER["layout"] = layout
    _WORKER["specs"] = specs
    _WORKER["generator"] = WaferGenerator(layout, GenerationSettings.from_config(config), int(config["random"]["master_seed"]))
    _WORKER["contexts"] = [(plan.n_shots, LevelContext(layout, train_mark_mask(layout, plan.shot_indices), config, specs)) for plan in plans]


def evaluate_wafer(wafer_id: int, generator: WaferGenerator, contexts: list, specs: list[MethodSpec], keep_estimates: bool = False):
    """1枚の Wafer を全 Shot 数・全手法で評価する。keep_estimates なら推定値も返す。"""
    sample = generator.generate(wafer_id)
    rows, estimates = [], {}
    for n_shots, context in contexts:
        measured_train = sample.measured[context.train_mask]
        truth_test = sample.truth[context.test_mask]
        for spec in specs:
            row = {
                "wafer": wafer_id,
                "n_shots": n_shots,
                "method": spec.method,
                "family": spec.family,
                "feature_set": spec.feature_set,
                "variant": spec.variant,
                "factor_mode": spec.factor_mode,
            }
            try:
                output = context.run(spec.method, measured_train)
                if not np.all(np.isfinite(output.estimate)):
                    raise FloatingPointError("推定値に NaN・無限大がある")
                row.update(wafer_metrics(truth_test, output.estimate, output.edf, context.outer_mask))
                row.update(
                    {
                        "edf_X": output.edf[0],
                        "edf_Y": output.edf[1],
                        "aux_X": output.aux[0],
                        "aux_Y": output.aux[1],
                        "iter_X": output.iterations[0],
                        "iter_Y": output.iterations[1],
                        "converged": bool(output.converged),
                        "seconds": output.seconds,
                        "error": "",
                    }
                )
                row.update(output.extra)
                if keep_estimates:
                    estimates[(n_shots, spec.method)] = output.estimate
            except Exception as exc:  # 1つの手法の失敗で全体を止めず、記録して次へ進む
                row.update({"converged": False, "seconds": float("nan"), "error": f"{type(exc).__name__}: {exc}"[:200]})
            rows.append(row)
    return rows, estimates, sample


def _run_chunk(task: tuple[int, list[int], str]) -> tuple[int, int, float]:
    chunk_id, wafer_ids, output_path = task
    start = time.perf_counter()
    rows = []
    for wafer_id in wafer_ids:
        wafer_rows, _, _ = evaluate_wafer(wafer_id, _WORKER["generator"], _WORKER["contexts"], _WORKER["specs"])
        rows.extend(wafer_rows)
    frame = pd.DataFrame(rows)
    temporary = output_path + ".tmp"
    frame.to_csv(temporary, index=False, float_format="%.6g", compression="gzip")
    os.replace(temporary, output_path)
    return chunk_id, len(rows), time.perf_counter() - start


def write_layout_tables(layout: WaferLayout, plans: list[SamplingPlan], tables_dir: Path) -> None:
    layout.shots.to_csv(tables_dir / "layout_shots.csv", index=False)
    layout.marks.to_csv(tables_dir / "layout_marks.csv", index=False, float_format="%.6g")
    records = []
    for plan in plans:
        shot_numbers = layout.shots["shotNo"].to_numpy()[plan.shot_indices]
        records.append(
            {
                "n_shots": plan.n_shots,
                "n_train_marks": int(train_mark_mask(layout, plan.shot_indices).sum()),
                "i_criterion": plan.criterion_value,
                "feasible": plan.feasible,
                "shotNo": " ".join(str(int(v)) for v in shot_numbers),
            }
        )
    pd.DataFrame(records).to_csv(tables_dir / "sampling_plans.csv", index=False)


def save_samples(config: dict, plans: list[SamplingPlan], samples_dir: Path) -> None:
    """図に使う代表 Wafer の真値・計測値・全手法の推定値を保存する。"""
    _init_worker(config, plans)
    arrays = {}
    for wafer_id in SAMPLE_WAFERS:
        if wafer_id >= int(config["generation"]["n_wafers"]):
            continue
        _, estimates, sample = evaluate_wafer(wafer_id, _WORKER["generator"], _WORKER["contexts"], _WORKER["specs"], keep_estimates=True)
        prefix = f"w{wafer_id}"
        for name in ("trend", "mark_offset", "scan_offset", "noise"):
            arrays[f"{prefix}__{name}"] = getattr(sample, name)
        for (n_shots, method), estimate in estimates.items():
            arrays[f"{prefix}__est__{n_shots}__{method}"] = estimate
    np.savez_compressed(samples_dir / "sample_predictions.npz", **arrays)


def run(config: dict, n_workers: int) -> Path:
    results_dir = Path(config["output"]["results_dir"])
    tables_dir = results_dir / "tables"
    chunks_dir = results_dir / "chunks"
    samples_dir = results_dir / "samples"
    for folder in (tables_dir, chunks_dir, samples_dir):
        folder.mkdir(parents=True, exist_ok=True)
    with open(results_dir / "config_used.json", "w", encoding="utf-8") as handle:
        json.dump(config, handle, ensure_ascii=False, indent=2)

    layout = build_layout(config)
    GenerationSettings.from_config(config)  # 設定の検証
    start = time.perf_counter()
    plans = build_plans(layout, config)
    print(f"サンプリング計画：{[p.n_shots for p in plans]} Shot（{time.perf_counter() - start:.0f} 秒）", flush=True)
    write_layout_tables(layout, plans, tables_dir)

    n_wafers = int(config["generation"]["n_wafers"])
    per_chunk = int(config["output"]["wafers_per_chunk"])
    tasks = []
    for chunk_id, first in enumerate(range(0, n_wafers, per_chunk)):
        wafer_ids = list(range(first, min(first + per_chunk, n_wafers)))
        path = chunks_dir / f"metrics_{wafer_ids[0]:04d}_{wafer_ids[-1]:04d}.csv.gz"
        if not path.exists():
            tasks.append((chunk_id, wafer_ids, str(path)))
    print(f"Wafer {n_wafers} 枚、未計算の chunk {len(tasks)} 個、手法 {len(build_method_specs(config))} 種類", flush=True)

    status_path = results_dir / "run_status.txt"
    run_start = time.perf_counter()
    if tasks:
        if n_workers <= 1:
            _init_worker(config, plans)
            iterator = map(_run_chunk, tasks)
            pool = None
        else:
            import multiprocessing as mp

            pool = mp.get_context("spawn").Pool(n_workers, initializer=_init_worker, initargs=(config, plans))
            iterator = pool.imap_unordered(_run_chunk, tasks)
        for done, (chunk_id, n_rows, seconds) in enumerate(iterator, start=1):
            elapsed = time.perf_counter() - run_start
            remaining = elapsed / done * (len(tasks) - done)
            message = f"chunk {done}/{len(tasks)} 完了（{seconds:.0f} 秒、経過 {elapsed / 60:.1f} 分、残り約 {remaining / 60:.1f} 分）"
            print(message, flush=True)
            status_path.write_text(message + "\n", encoding="utf-8")
        if pool is not None:
            pool.close()
            pool.join()

    frames = [pd.read_csv(path) for path in sorted(chunks_dir.glob("metrics_*.csv.gz"))]
    metrics = pd.concat(frames, ignore_index=True)
    metrics = metrics[metrics["wafer"] < n_wafers]
    output = tables_dir / "per_wafer_metrics.csv.gz"
    metrics.to_csv(output, index=False, float_format="%.6g", compression="gzip")
    n_errors = int((metrics["error"].fillna("") != "").sum())
    print(f"全 {len(metrics)} 行を {output} に保存（失敗 {n_errors} 行）", flush=True)

    save_samples(config, plans, samples_dir)
    run_info = {
        "seconds_total": time.perf_counter() - start,
        "n_wafers": n_wafers,
        "n_rows": int(len(metrics)),
        "n_errors": n_errors,
        "python": sys.version.split()[0],
        "platform": platform.platform(),
        "numpy": np.__version__,
        "pandas": pd.__version__,
    }
    with open(results_dir / "run_info.json", "w", encoding="utf-8") as handle:
        json.dump(run_info, handle, ensure_ascii=False, indent=2)
    return output


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="アライメント計測値の面内推定：手法と説明変数の比較")
    parser.add_argument("--config", default="config/default.json")
    parser.add_argument("--n-wafers", type=int, default=None, help="Wafer 枚数を上書き（動作確認用）")
    parser.add_argument("--results-dir", default=None, help="結果の保存先を上書き")
    parser.add_argument("--workers", type=int, default=None, help="並列プロセス数を上書き")
    args = parser.parse_args(argv)
    config = copy.deepcopy(load_config(args.config))
    if args.n_wafers is not None:
        if args.n_wafers < 1:
            raise SystemExit("--n-wafers は1以上")
        config["generation"]["n_wafers"] = args.n_wafers
    if args.results_dir is not None:
        config["output"]["results_dir"] = args.results_dir
    workers = args.workers if args.workers is not None else int(config["output"]["n_workers"])
    run(config, max(1, workers))


if __name__ == "__main__":
    main()
