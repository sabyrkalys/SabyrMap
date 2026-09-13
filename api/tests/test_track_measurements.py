import pytest

from app.services.track_measurements import compute_elevation_gain_meters, compute_length_meters


def test_compute_length_meters_one_degree_of_latitude():
    coords = [(0.0, 0.0, 0.0), (0.0, 1.0, 0.0)]
    assert compute_length_meters(coords) == pytest.approx(111195, rel=1e-3)


def test_compute_length_meters_sums_multiple_segments():
    coords = [(0.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 2.0, 0.0)]
    single_segment = compute_length_meters([(0.0, 0.0, 0.0), (0.0, 1.0, 0.0)])
    assert compute_length_meters(coords) == pytest.approx(single_segment * 2, rel=1e-6)


def test_compute_length_meters_single_point_is_zero():
    assert compute_length_meters([(0.0, 0.0, 0.0)]) == 0.0


def test_compute_elevation_gain_monotonic_climb():
    coords = [(0.0, 0.0, 100.0), (0.0, 0.0, 105.0), (0.0, 0.0, 110.0), (0.0, 0.0, 115.0)]
    assert compute_elevation_gain_meters(coords) == pytest.approx(15.0)


def test_compute_elevation_gain_ignores_noise_below_threshold():
    coords = [(0.0, 0.0, 100.0), (0.0, 0.0, 101.0), (0.0, 0.0, 99.0), (0.0, 0.0, 102.0), (0.0, 0.0, 100.0)]
    assert compute_elevation_gain_meters(coords) == 0.0


def test_compute_elevation_gain_climb_drop_climb_past_threshold():
    coords = [(0.0, 0.0, 100.0), (0.0, 0.0, 104.0), (0.0, 0.0, 101.0), (0.0, 0.0, 108.0)]
    assert compute_elevation_gain_meters(coords) == pytest.approx(8.0)


def test_compute_elevation_gain_single_point_is_zero():
    assert compute_elevation_gain_meters([(0.0, 0.0, 100.0)]) == 0.0


def test_compute_elevation_gain_out_and_back():
    coords = [(0.0, 0.0, 100.0), (0.0, 0.0, 200.0), (0.0, 0.0, 100.0)]
    assert compute_elevation_gain_meters(coords) == pytest.approx(100.0)


def test_compute_elevation_gain_out_and_back_and_reclimb():
    coords = [(0.0, 0.0, 100.0), (0.0, 0.0, 200.0), (0.0, 0.0, 100.0), (0.0, 0.0, 200.0)]
    assert compute_elevation_gain_meters(coords) == pytest.approx(200.0)
