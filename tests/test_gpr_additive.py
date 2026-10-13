import numpy as np
import pytest
from scipy.optimize import approx_fprime

from src.basis import distance_features, factor_design, feature_groups, interaction_design, interaction_levels
from src.methods import build_method_specs
from src.models.gpr import CategoricalComponent, GaussianProcess, KernelSpec, PairwiseGeometry, fit_predict_gpr
from src.wafer_generator import GenerationSettings, WaferGenerator


@pytest.fixture(scope="module")
def problem():
    rng = np.random.default_rng(11)
    n_train, n_test = 64, 40
    radius = 140 * np.sqrt(rng.uniform(size=n_train + n_test))
    angle = rng.uniform(-np.pi, np.pi, size=n_train + n_test)
    x, y = radius * np.cos(angle), radius * np.sin(angle)
    direction = rng.integers(1, 3, n_train + n_test)
    mark = rng.integers(1, 5, n_train + n_test)
    features = distance_features(x, y, "XYR", 150.0)
    geometry = PairwiseGeometry.build(features[:n_train], features[n_train:], feature_groups("XYR"))
    factors = factor_design(direction, mark, 4)
    effects = np.array([1.2, 1.5, -0.8, 0.4])
    smooth = 3 * (x / 150) ** 2 - 2 * (y / 150) + np.sin(2 * x / 150)
    values = smooth + factors @ effects
    noisy = values[:n_train] + 0.1 * rng.normal(size=n_train)
    components = {
        "scan": CategoricalComponent.build("scan", direction[:n_train], direction[n_train:]),
        "mark": CategoricalComponent.build("mark", mark[:n_train], mark[n_train:]),
        "scan_mark": CategoricalComponent.build(
            "scan_mark", interaction_levels(direction[:n_train], mark[:n_train]), interaction_levels(direction[n_train:], mark[n_train:])
        ),
    }
    return {"geometry": geometry, "factors": factors, "values": values, "noisy": noisy, "components": components, "n_train": n_train,
            "direction": direction, "mark": mark}


@pytest.mark.parametrize("kernel", ["matern52", "ardrationalquadratic", "squaredexponential"])
@pytest.mark.parametrize("names", [("scan", "mark"), ("scan", "mark", "scan_mark")])
def test_additive_gradient_matches_finite_difference(problem, kernel, names):
    gp = GaussianProcess(KernelSpec.parse(kernel), problem["geometry"], categorical=tuple(problem["components"][n] for n in names))
    target = problem["noisy"]
    basis = np.ones((problem["n_train"], 1))
    params = gp.initial_log_params(target) + 0.15
    assert params.size == gp.n_params
    _, gradient = gp.objective(params, target, basis)
    numeric = approx_fprime(params, lambda p: gp.objective(p, target, basis)[0], 1e-6)
    np.testing.assert_allclose(gradient, numeric, rtol=1e-4, atol=1e-4)


def test_additive_with_large_tau_equals_basis(problem):
    """質的変数の項の τ → ∞ では、加法カーネルの推定値が基底関数で同時推定した推定値（GLS）に一致する。

    τ を大きくしすぎると condition() の数値安定化の項（共分散のトレースに比例）が効いてずれるので、
    標準偏差の30倍で確かめる（この時点で差は 1e-5 未満）。
    """
    n = problem["n_train"]
    kernel = KernelSpec.parse("matern52")
    plain = GaussianProcess(kernel, problem["geometry"])
    additive = GaussianProcess(kernel, problem["geometry"], categorical=(problem["components"]["scan"], problem["components"]["mark"]))
    target = problem["noisy"]
    factors = problem["factors"]
    spatial = plain.fit(target, np.hstack([np.ones((n, 1)), factors[:n]])).log_params
    big = np.log(30.0 * np.std(target))
    params = np.concatenate([spatial[:-1], [big, big], spatial[-1:]])
    basis_fit = plain.condition(spatial, target, np.hstack([np.ones((n, 1)), factors[:n]]))
    basis_prediction = plain.predict(basis_fit, np.hstack([np.ones((len(factors) - n, 1)), factors[n:]]))
    additive_fit = additive.condition(params, target, np.ones((n, 1)))
    additive_prediction = additive.predict(additive_fit, np.ones((len(factors) - n, 1)))
    np.testing.assert_allclose(additive_prediction, basis_prediction, atol=1e-4)


def test_additive_mode_recovers_offsets_and_shrinks_when_absent(problem):
    n = problem["n_train"]
    gp = GaussianProcess(KernelSpec.parse("squaredexponential"), problem["geometry"],
                         categorical=(problem["components"]["scan"], problem["components"]["mark"]))
    factors = problem["factors"]
    with_effects = fit_predict_gpr(gp, problem["noisy"], factors[:n], factors[n:], "additive")
    error = np.sqrt(np.mean((with_effects.prediction - problem["values"][n:]) ** 2))
    none = fit_predict_gpr(GaussianProcess(KernelSpec.parse("squaredexponential"), problem["geometry"]), problem["noisy"],
                           factors[:n], factors[n:], "none")
    assert error < 0.5 * np.sqrt(np.mean((none.prediction - problem["values"][n:]) ** 2))
    # 質的変数の効果がないデータでは τ が小さく推定される（効果を0へ縮める）
    no_effect = problem["noisy"] - factors[:n] @ np.array([1.2, 1.5, -0.8, 0.4])
    shrunk = fit_predict_gpr(gp, no_effect, factors[:n], factors[n:], "additive")
    tau = gp.categorical_std(shrunk.log_params)
    assert max(tau.values()) < 0.3 * np.std(no_effect)


def test_interaction_design_columns():
    direction = np.array([1, 1, 2, 2, 1, 2, 1, 2])
    mark = np.array([1, 4, 1, 4, 2, 2, 3, 3])
    columns = interaction_design(direction, mark, 4)
    assert columns.shape == (8, 3)
    np.testing.assert_array_equal(columns[0], [1, 0, 0])
    np.testing.assert_array_equal(columns[3], [1, 1, 1])  # 方向2（−1）× Mark4（−1, −1, −1）
    assert len(set(interaction_levels(direction, mark))) == 8


def test_generator_interaction_changes_only_scan_offset(layout, config):
    base = WaferGenerator(layout, GenerationSettings.from_config(config), 5).generate(2)
    gen_cfg = {**config["generation"], "scan_mark_interaction_std_nm": 1.0}
    other = WaferGenerator(layout, GenerationSettings.from_config({**config, "generation": gen_cfg}), 5).generate(2)
    np.testing.assert_array_equal(base.trend, other.trend)
    np.testing.assert_array_equal(base.mark_offset, other.mark_offset)
    np.testing.assert_array_equal(base.noise, other.noise)
    assert not np.allclose(base.scan_offset, other.scan_offset)
    np.testing.assert_array_equal(base.scan_mark_interaction, 0.0)
    # Scan 差（方向1 − 方向2）が Mark ごとに変わる
    up = layout.direction == 1
    differences = []
    for mark in range(1, 5):
        rows = layout.mark_number == mark
        differences.append(other.scan_offset[rows & up][0] - other.scan_offset[rows & ~up][0])
    assert np.ptp(np.array(differences)[:, 0]) > 0.1


def test_method_families_filter(config):
    cfg = {**config, "methods": {**config["methods"], "families": ["GPR"], "gpr_factor_modes": ["additive"]}}
    specs = build_method_specs(cfg)
    assert {spec.family for spec in specs} == {"GPR"}
    assert {spec.factor_mode for spec in specs} == {"additive"}
    with pytest.raises(ValueError):
        build_method_specs({**config, "methods": {**config["methods"], "families": ["SVR"]}})


def test_mixed_with_large_tau_equals_basis(problem):
    """mixed（Scan方向は基底関数、Mark番号は加法カーネル）も τ → ∞ で同時推定と一致する。"""
    n = problem["n_train"]
    kernel = KernelSpec.parse("matern52")
    plain = GaussianProcess(kernel, problem["geometry"])
    mixed = GaussianProcess(kernel, problem["geometry"], categorical=(problem["components"]["mark"],))
    target = problem["noisy"]
    factors = problem["factors"]
    full_train = np.hstack([np.ones((n, 1)), factors[:n]])
    full_test = np.hstack([np.ones((len(factors) - n, 1)), factors[n:]])
    spatial = plain.fit(target, full_train).log_params
    params = np.concatenate([spatial[:-1], [np.log(30.0 * np.std(target))], spatial[-1:]])
    basis_prediction = plain.predict(plain.condition(spatial, target, full_train), full_test)
    mixed_fit = mixed.condition(params, target, full_train[:, :2])
    np.testing.assert_allclose(mixed.predict(mixed_fit, full_test[:, :2]), basis_prediction, atol=1e-4)


def test_mixed_mode_runs_through_level_context(layout, config):
    from src.methods import LevelContext
    from src.sampling import train_mark_mask

    cfg = {**config, "methods": {**config["methods"], "families": ["GPR"], "gpr_kernels": ["matern52"], "feature_sets": ["XY"],
                                 "gpr_factor_modes": ["mixed", "mixed_int"]}}
    specs = build_method_specs(cfg)
    shots = np.arange(0, layout.n_shots, 4)
    context = LevelContext(layout, train_mark_mask(layout, shots), cfg, specs)
    measured = WaferGenerator(layout, GenerationSettings.from_config(config), 3).generate(0).measured[context.train_mask]
    for spec in specs:
        output = context.run(spec.method, measured)
        assert np.all(np.isfinite(output.estimate))
        assert "tau_mark_X" in output.extra and "tau_scan_X" not in output.extra
