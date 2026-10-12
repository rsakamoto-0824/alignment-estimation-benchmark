import numpy as np
import pytest

from src.metrics import regression_metrics, wafer_metrics
from src.sampling import constrained_i_optimal, constraint_partitions, group_bounds, i_criterion, shot_information, violation_count


def test_i_optimal_plan_meets_constraints(layout, config):
    constraints = config["sampling"]["constraints"]
    plan = constrained_i_optimal(layout, 10, 5, constraints, np.random.default_rng(0), n_starts=2, max_iterations=30)
    partitions = constraint_partitions(layout, constraints)
    bounds = group_bounds(partitions, 10, constraints["slack"])
    mask = np.zeros(layout.n_shots, dtype=bool)
    mask[plan.shot_indices] = True
    assert plan.feasible and violation_count(mask, partitions, bounds) == 0
    assert len(plan.shot_indices) == 10
    # Scan方向は両方とも含む（質的変数を推定できる）
    assert set(layout.shots["Direction"].to_numpy()[plan.shot_indices]) == {1, 2}


def test_i_criterion_decreases_when_adding_shots(layout):
    info = shot_information(layout, 5)
    order = np.random.default_rng(1).permutation(layout.n_shots)
    values = [i_criterion(info[order[:k]].sum(axis=0)) for k in (8, 15, 30, 60)]
    assert all(a > b for a, b in zip(values, values[1:]))


def test_regression_metrics():
    truth = np.array([1.0, 2.0, 3.0, 4.0])
    perfect = regression_metrics(truth, truth, edf=2)
    assert perfect["R2"] == pytest.approx(1.0) and perfect["RMSE"] == 0.0 and perfect["MAE"] == 0.0
    estimate = truth + np.array([1.0, -1.0, 1.0, -1.0])
    result = regression_metrics(truth, estimate, edf=2)
    assert result["RMSE"] == pytest.approx(1.0) and result["MAE"] == pytest.approx(1.0)
    r2 = 1 - 4 / 5
    assert result["R2"] == pytest.approx(r2)
    assert result["adjR2"] == pytest.approx(1 - (1 - r2) * 3 / 2)
    assert np.isnan(regression_metrics(truth, estimate, edf=4)["adjR2"])


def test_wafer_metrics_xy_pooling():
    rng = np.random.default_rng(0)
    truth = rng.normal(size=(30, 2)) + np.array([5.0, -5.0])
    estimate = truth + rng.normal(scale=0.1, size=truth.shape)
    result = wafer_metrics(truth, estimate, (3.0, 3.0), np.arange(30) < 10)
    assert result["RMSE_XY"] == pytest.approx(np.sqrt(np.mean((truth - estimate) ** 2)))
    # 軸ごとの平均の違い（±5）は R²_XY の分母に入れない
    assert result["R2_XY"] < 1 and result["R2_XY"] == pytest.approx(min(result["R2_X"], result["R2_Y"]), abs=0.05)
