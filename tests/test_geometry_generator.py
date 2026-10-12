import numpy as np
import pytest

from src.basis import distance_features, effect_coding, factor_design, feature_groups, polynomial_design
from src.geometry import SCAN_UP, rt_to_xy, xy_to_rt
from src.wafer_generator import GenerationSettings, WaferGenerator, noise_halfwidth


def test_layout_marks_inside_usable_radius(layout, config):
    usable = config["wafer"]["diameter_mm"] / 2 - config["wafer"]["edge_exclusion_mm"]
    assert layout.n_shots == 99
    assert layout.n_marks == 4 * layout.n_shots
    assert np.all(layout.radius_mm < usable)
    marks = layout.marks
    np.testing.assert_allclose(marks["x_mm"], marks["Xmm"] + marks["markXmm"])
    np.testing.assert_allclose(marks["Radius"], np.hypot(marks["Xmm"], marks["Ymm"]))


def test_scan_direction_alternates_by_column(layout):
    shots = layout.shots
    for column, direction in zip(shots["column"], shots["Direction"]):
        assert direction == (1 if column % 2 == 0 else 2)


def test_rt_round_trip():
    rng = np.random.default_rng(1)
    u, v, theta = rng.normal(size=(3, 50))
    np.testing.assert_allclose(rt_to_xy(*xy_to_rt(u, v, theta), theta), (u, v), atol=1e-12)


def test_generator_is_reproducible_and_components_add_up(layout, config):
    generator = WaferGenerator(layout, GenerationSettings.from_config(config), 123)
    first, again = generator.generate(5), generator.generate(5)
    np.testing.assert_array_equal(first.measured, again.measured)
    np.testing.assert_allclose(first.truth, first.trend + first.mark_offset + first.scan_offset)
    np.testing.assert_allclose(first.measured, first.truth + first.noise)
    n_terms = (first.trend_coefficients != 0).sum(axis=0)
    assert np.all((n_terms >= 10) & (n_terms <= 30))
    # Scan方向の差：方向1 − 方向2 = δ
    up = layout.direction == SCAN_UP
    np.testing.assert_allclose(first.scan_offset[up][0] - first.scan_offset[~up][0], first.scan_difference)
    # Mark番号ごとのオフセットは全Shotで共通
    for mark in range(1, 5):
        rows = first.mark_offset[layout.mark_number == mark]
        np.testing.assert_allclose(rows, rows[0][None, :].repeat(len(rows), axis=0))


def test_noise_is_bounded_and_grows_to_edge(layout, config):
    settings = GenerationSettings.from_config(config)
    width = noise_halfwidth(layout.radius_mm, settings)
    assert width.max() == pytest.approx(3.0)
    assert width.min() >= 1.0
    generator = WaferGenerator(layout, settings, 7)
    noise = np.vstack([generator.generate(w).noise for w in range(20)])
    assert np.all(np.abs(noise) <= np.tile(width, 20)[:, None] + 1e-12)


def test_noise_settings_do_not_change_trend(layout, config):
    settings = GenerationSettings.from_config(config)
    other = GenerationSettings.from_config({**config, "generation": {**config["generation"], "noise_halfwidth_edge_nm": 5.0}})
    a = WaferGenerator(layout, settings, 9).generate(3)
    b = WaferGenerator(layout, other, 9).generate(3)
    np.testing.assert_array_equal(a.trend, b.trend)
    np.testing.assert_array_equal(a.mark_offset, b.mark_offset)


def test_effect_coding_and_features():
    coding = effect_coding(np.array([1, 2, 3, 3]), np.array([1, 2, 3]))
    np.testing.assert_array_equal(coding, [[1, 0], [0, 1], [-1, -1], [-1, -1]])
    factors = factor_design(np.array([1, 2]), np.array([1, 4]), 4)
    assert factors.shape == (2, 4)
    features = distance_features(np.array([150.0]), np.array([0.0]), "XYRT", 150.0)
    np.testing.assert_allclose(features, [[1.0, 0.0, 1.0, 1.0, 0.0]])
    np.testing.assert_array_equal(feature_groups("XYRT"), [0, 1, 2, 3, 3])
    assert polynomial_design(np.zeros(3), np.zeros(3), 5).shape == (3, 21)
