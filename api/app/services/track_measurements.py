import math

_EARTH_RADIUS_METERS = 6371000.0
_ELEVATION_NOISE_THRESHOLD_METERS = 3.0


def _haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * _EARTH_RADIUS_METERS * math.asin(math.sqrt(a))


def compute_length_meters(coords: list[tuple[float, float, float]]) -> float:
    """2D ground distance along the track, ignoring elevation."""
    total = 0.0
    for (lon1, lat1, _), (lon2, lat2, _) in zip(coords, coords[1:]):
        total += _haversine_meters(lat1, lon1, lat2, lon2)
    return total


def compute_elevation_gain_meters(coords: list[tuple[float, float, float]]) -> float:
    """Sum of sustained climbs, smoothing GPS altitude noise with a 3m threshold.

    Tracks a baseline elevation; a delta only counts (and resets the baseline
    upward) once a sustained climb exceeds the noise threshold. A sustained
    descent (also past the threshold) re-arms the baseline downward without
    adding to the gain, so a later re-climb past the same or a new peak is
    correctly counted again — jitter within the threshold in either direction
    is ignored either way.
    """
    if len(coords) < 2:
        return 0.0
    gain = 0.0
    baseline = coords[0][2]
    for _, _, elevation in coords[1:]:
        delta = elevation - baseline
        if delta > _ELEVATION_NOISE_THRESHOLD_METERS:
            gain += delta
            baseline = elevation
        elif -delta > _ELEVATION_NOISE_THRESHOLD_METERS:
            baseline = elevation
    return gain
