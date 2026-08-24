import pandas as pd
from train_crowd_model import FEATURE_COLUMNS, _ensure_feature_columns


def test_ensure_feature_columns_adds_columns():
    df = pd.DataFrame({"occupancy_level": [3]})
    enriched = _ensure_feature_columns(df)
    for col in FEATURE_COLUMNS:
        assert col in enriched.columns
