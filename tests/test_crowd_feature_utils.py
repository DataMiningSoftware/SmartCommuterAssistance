from crowd_feature_utils import normalize_route_id


def test_normalize_route_id_basic():
    assert normalize_route_id("KJ", "KJ15") == "KJ"
    assert normalize_route_id("kg", "KG05") == "MRT"
    assert normalize_route_id("py17", "PY17") == "PYL"
    # when route is missing, the function infers from stop_id -> 'SP' -> maps to 'PH'
    assert normalize_route_id("", "SP15") == "PH"
