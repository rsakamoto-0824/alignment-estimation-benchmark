import numpy as np
import pytest
from scipy.optimize import approx_fprime

from src.basis import distance_features, factor_design, feature_groups, polynomial_design
from src.models.gam import AdditiveModel, cyclic_bspline_basis
from src.models.gpr import KERNEL_NAMES, GaussianProcess, KernelSpec, PairwiseGeometry, fit_predict_gpr
from src.models.kriging import Kriging, variogram_function
from src.models.linear_models import polynomial_operator, rt_design, rt_operator
from src.models.tps import ThinPlateSpline


@pytest.fixture(scope="module")
def points():
    rng = np.random.default_rng(3)
    radius = 140 * np.sqrt(rng.uniform(size=90))
    angle = rng.uniform(-np.pi, np.pi, size=90)
    return radius * np.cos(angle), radius * np.sin(angle)


def _geometry(x, y, feature_set, n_train):
    features = distance_features(x, y, feature_set, 150.0)
    return PairwiseGeometry.build(features[:n_train], features[n_train:], feature_groups(feature_set))


@pytest.mark.parametrize("kernel", KERNEL_NAMES)
def test_gpr_gradient_matches_finite_difference(points, kernel):
    x, y = points
    geometry = _geometry(x, y, "XYRT", 60)
    gp = GaussianProcess(KernelSpec.parse(kernel), geometry)
    target = np.sin(3 * x[:60] / 150) * 4 + 0.3 * np.random.default_rng(0).normal(size=60)
    basis = np.ones((60, 1))
    params = gp.initial_log_params(target) + 0.2
    value, gradient = gp.objective(params, target, basis)
    numeric = approx_fprime(params, lambda p: gp.objective(p, target, basis)[0], 1e-6)
    np.testing.assert_allclose(gradient, numeric, rtol=1e-4, atol=1e-4)


def test_backfitting_limit_equals_joint_gls(points):
    """超パラメータを固定して GPR と質的変数を交互に当てはめ直すと、質的変数を基底に入れた GLS の解に収束する。"""
    x, y = points
    n = 60
    geometry = _geometry(x, y, "XY", n)
    gp = GaussianProcess(KernelSpec.parse("matern52"), geometry)
    rng = np.random.default_rng(1)
    factors = factor_design(rng.integers(1, 3, n), rng.integers(1, 5, n), 4)
    target = np.cos(2 * y[:n] / 150) * 3 + factors @ np.array([1.0, 0.5, -0.7, 0.2]) + 0.2 * rng.normal(size=n)
    params = gp.fit(target, np.ones((n, 1))).log_params
    design = factors - factors.mean(axis=0)
    ones = np.ones((n, 1))
    effects = np.zeros(4)
    for _ in range(3000):
        fit = gp.condition(params, target - design @ effects, ones)
        smooth = gp.fitted_train(fit, ones)
        effects = np.linalg.lstsq(design, target - smooth, rcond=None)[0]
    joint = gp.condition(params, target, np.hstack([ones, design]))
    np.testing.assert_allclose(effects, joint.beta[1:], atol=1e-6)


def test_gpr_factor_modes_recover_offsets(points):
    x, y = points
    n = 60
    geometry = _geometry(x, y, "XY", n)
    gp = GaussianProcess(KernelSpec.parse("squaredexponential"), geometry)
    rng = np.random.default_rng(2)
    factors = factor_design(rng.integers(1, 3, 90), rng.integers(1, 5, 90), 4)
    true_effects = np.array([1.5, 2.0, -1.0, 0.5])
    smooth = 4 * (x / 150) ** 2 - 3 * (y / 150)
    values = smooth + factors @ true_effects
    noisy = values[:n] + 0.05 * rng.normal(size=n)
    errors = {}
    for mode in ("none", "basis", "backfit"):
        result = fit_predict_gpr(gp, noisy, factors[:n], factors[n:], mode)
        errors[mode] = np.sqrt(np.mean((result.prediction - values[n:]) ** 2))
        if mode != "none":
            np.testing.assert_allclose(result.factor_effects, true_effects, atol=0.2)
    assert errors["basis"] < 0.5 * errors["none"]
    assert errors["backfit"] == pytest.approx(errors["basis"], rel=0.1)


def test_tps_reproduces_linear_function(points):
    x, y = points
    features = distance_features(x, y, "XYR", 150.0)
    tps = ThinPlateSpline(features[:60], features[60:], np.linspace(-8, 3, 23))
    target = 2.0 + 3.0 * features[:, 0] - features[:, 1] + 0.5 * features[:, 2]
    result = tps.fit_predict(target[:60])
    np.testing.assert_allclose(result.prediction, target[60:], atol=1e-8)
    assert 4 <= result.edf <= 60


def test_variogram_formulas_match_pykrige_definitions():
    d = np.array([0.0, 0.5, 1.0])
    np.testing.assert_allclose(variogram_function("linear", np.array([2.0, 0.1]), d), 2 * d + 0.1)
    np.testing.assert_allclose(variogram_function("power", np.array([2.0, 1.5, 0.1]), d), 2 * d**1.5 + 0.1)
    np.testing.assert_allclose(
        variogram_function("gaussian", np.array([3.0, 1.0, 0.1]), d), 3 * (1 - np.exp(-(d**2) / (4 / 7) ** 2)) + 0.1
    )
    np.testing.assert_allclose(
        variogram_function("exponential", np.array([3.0, 1.0, 0.1]), d), 3 * (1 - np.exp(-d / (1 / 3))) + 0.1
    )


@pytest.mark.parametrize("variogram", ["linear", "gaussian", "power", "exponential"])
def test_universal_kriging_reproduces_linear_drift(points, variogram):
    x, y = points
    features = distance_features(x, y, "XY", 150.0)
    target = 1.0 + 2.0 * features[:, 0] - 3.0 * features[:, 1]
    kriging = Kriging(features[:60], features[60:], "universal", variogram)
    result = kriging.fit_predict(target[:60])
    np.testing.assert_allclose(result.prediction, target[60:], atol=1e-5)
    ordinary = Kriging(features[:60], features[60:], "ordinary", variogram).fit_predict(np.full(60, 4.2))
    np.testing.assert_allclose(ordinary.prediction, 4.2, atol=1e-8)


def test_cyclic_basis_is_periodic_partition_of_unity():
    theta = np.linspace(-np.pi, np.pi, 50)
    basis = cyclic_bspline_basis(theta, -np.pi, 2 * np.pi, 8)
    np.testing.assert_allclose(basis.sum(axis=1), 1.0)
    np.testing.assert_allclose(basis[0], basis[-1], atol=1e-12)


def test_gam_recovers_factor_effects(points):
    x, y = points
    rng = np.random.default_rng(4)
    factors = factor_design(rng.integers(1, 3, 90), rng.integers(1, 5, 90), 4)
    pts = {"x": x / 150, "y": y / 150, "r": np.hypot(x, y) / 150, "theta": np.arctan2(y, x)}
    train = {k: v[:70] for k, v in pts.items()}
    test = {k: v[70:] for k, v in pts.items()}
    values = 3 * pts["x"] * pts["y"] + 2 * pts["r"] ** 2 + factors @ np.array([1.0, -2.0, 0.5, 0.8])
    model = AdditiveModel(train, test, "XYRT", factors[:70], factors[70:])
    result = model.fit_predict(values[:70] + 0.05 * rng.normal(size=70))
    assert np.sqrt(np.mean((result.prediction - values[70:]) ** 2)) < 0.3
    assert result.edf < 70


def test_polynomial_operator_recovers_order5(points):
    x, y = points
    xy = np.column_stack([x, y]) / 150
    coef = np.random.default_rng(5).normal(size=(21, 2))
    values = polynomial_design(xy[:, 0], xy[:, 1], 5) @ coef
    operator = polynomial_operator(xy[:60], xy[60:], 5)
    np.testing.assert_allclose(operator.apply(values[:60]), values[60:], atol=1e-8)
    assert operator.edf_x == pytest.approx(21) and operator.edf_y == pytest.approx(21)


def test_rt_operator_recovers_rt_field(points):
    x, y = points
    xy = np.column_stack([x, y]) / 150
    design = rt_design(xy, 4)
    coef = np.random.default_rng(6).normal(size=design.shape[1])
    stacked = design @ coef
    values = np.column_stack([stacked[:90], stacked[90:]])
    operator = rt_operator(xy[:60], xy[60:], 4)
    np.testing.assert_allclose(operator.apply(values[:60]), values[60:], atol=1e-8)
    assert operator.n_coef == 34
    assert operator.edf_x + operator.edf_y == pytest.approx(34)
