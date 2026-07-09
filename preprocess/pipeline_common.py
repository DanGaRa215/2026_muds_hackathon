"""パイプライン共通の定数・ヘルパー。

- 仕様書§5: 距離計算は JGD2011 平面直角座標系 第IX系 (EPSG:6677) で行う。
  Transformer は本モジュールで1個だけ生成して全工程で使い回す。
- 仕様書§3: 対象範囲(江戸川区行政界 + 1.5km バッファ、bbox フォールバック)
"""

from __future__ import annotations

import json
import logging
import sys
from pathlib import Path

from pyproj import Transformer

BASE_DIR = Path(__file__).resolve().parent
RAW_DIR = BASE_DIR / "data" / "raw"
INTERIM_DIR = BASE_DIR / "data" / "interim"
DEM_CACHE_DIR = INTERIM_DIR / "dem"
OUTPUT_DIR = BASE_DIR / "output"

# 中間ファイル
BOUNDARY_GEOJSON = INTERIM_DIR / "boundary_buffered.geojson"
GRAPH_GRAPHML = INTERIM_DIR / "graph_simplified.graphml"
WATER_GEOJSON = INTERIM_DIR / "water.geojson"
FETCH_INFO_JSON = INTERIM_DIR / "fetch_info.json"
NODES_PARQUET = INTERIM_DIR / "nodes.parquet"
EDGES_PARQUET = INTERIM_DIR / "edges.parquet"
EDGES_ELEV_PARQUET = INTERIM_DIR / "edges_elev.parquet"
SHELTERS_PARQUET = INTERIM_DIR / "shelters.parquet"

# 成果物
DB_PATH = OUTPUT_DIR / "routing.db"
VERIFICATION_JSON = OUTPUT_DIR / "verification.json"

# §3 行政界ポリゴンが取れない場合のフォールバック bbox
FALLBACK_BBOX = {"lat_min": 35.56, "lon_min": 139.81, "lat_max": 35.78, "lon_max": 139.93}
BUFFER_M = 1500.0

# §5 EPSG:4326 -> EPSG:6677 (JGD2011 平面直角座標系 第IX系)。1個生成して使い回す
TO_PLANE = Transformer.from_crs("EPSG:4326", "EPSG:6677", always_xy=True)
TO_WGS84 = Transformer.from_crs("EPSG:6677", "EPSG:4326", always_xy=True)

# 本家 overpass-api.de は本環境から HTTP 406 を返すため公式ミラーを使用
OVERPASS_URL = "https://lz4.overpass-api.de/api"

# 水域距離の打ち切り上限 (§6.2)
WATER_DIST_CLIP_M = 9999.0


def setup_logging(name: str) -> logging.Logger:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        stream=sys.stdout,
    )
    return logging.getLogger(name)


def write_json(path: Path, obj) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))
