"""03: 標高付与 (仕様書§6.4)

各エッジ中点の標高を国土地理院 標高タイル (dem5a zoom15、欠測は DEM10B=dem zoom14
でフォールバック) から取得して edges に付与する。それでも欠測なら 0.0 + 警告ログ。
"""

from __future__ import annotations

import sys

import pandas as pd

from elevation_util import get_elevation
from pipeline_common import EDGES_ELEV_PARQUET, EDGES_PARQUET, setup_logging

logger = setup_logging("03_fetch_elevation")


def main() -> int:
    edges = pd.read_parquet(EDGES_PARQUET)
    logger.info("%d エッジ中点の標高を取得中...", len(edges))

    elevations = []
    missing = 0
    for i, (lat, lon) in enumerate(zip(edges["mid_lat"], edges["mid_lon"]), start=1):
        value = get_elevation(lat, lon)
        if value is None:
            missing += 1
            logger.warning("標高欠測 (dem5a/dem とも): lat=%.6f lon=%.6f → 0.0", lat, lon)
            value = 0.0
        elevations.append(value)
        if i % 10000 == 0:
            logger.info("  %d / %d", i, len(edges))

    edges["elevation_m"] = elevations
    edges.to_parquet(EDGES_ELEV_PARQUET, index=False)
    logger.info(
        "03 完了: 欠測フォールバック(0.0) %d 件, 標高範囲 %.2f〜%.2f m",
        missing,
        edges["elevation_m"].min(),
        edges["elevation_m"].max(),
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
