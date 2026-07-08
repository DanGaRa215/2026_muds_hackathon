"""04: 避難所の取り込みとスナップ (仕様書§6.3)

- 入力: 国土地理院「指定緊急避難場所データ」の江戸川区分 CSV
  (既定: data/raw/shelters_edogawa.csv。--input で変更可)
- 入力が無ければ全国版 mergeFromCity_2.csv をダウンロードして江戸川区分を抽出
- types 語彙 (固定): flood, surge, earthquake, tsunami, fire, landslide, inland_flood
- elevation_m: §6.4 と同じ方法 / coast_distance_m: §6.2 と同じ STRtree
- nearest_node: ノードSTRtree で最近傍。200m超は警告ログ
"""

from __future__ import annotations

import argparse
import importlib
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import requests
from shapely.geometry import Point
from shapely.strtree import STRtree

from elevation_util import get_elevation
from pipeline_common import (
    NODES_PARQUET,
    RAW_DIR,
    SHELTERS_PARQUET,
    TO_PLANE,
    WATER_DIST_CLIP_M,
    setup_logging,
)

logger = setup_logging("04_build_shelters")

# 02_build_graph.py の水域STRtree構築を再利用 (ファイル名が数字始まりのため importlib)
build_graph = importlib.import_module("02_build_graph")

# 国土地理院 指定緊急避難場所データ(全国版CSV)。README に手順を記載
NATIONAL_CSV_URL = "https://hinanmap.gsi.go.jp/hinanjocp/defaultFtpData/csv/mergeFromCity_2.csv"
MUNICIPALITY = "東京都江戸川区"

COL_ID = "共通ID"
COL_MUNICIPALITY = "都道府県名及び市町村名"
COL_NAME = "施設・場所名"
COL_LAT = "緯度"
COL_LON = "経度"

# 災害種別カラム → 固定語彙 (§6.3)。語彙の列挙順で types を組み立てる。
# 元データの「火山現象」は語彙に無いため対象外
TYPE_COLUMNS = [
    ("洪水", "flood"),
    ("高潮", "surge"),
    ("地震", "earthquake"),
    ("津波", "tsunami"),
    ("大規模な火事", "fire"),
    ("崖崩れ、土石流及び地滑り", "landslide"),
    ("内水氾濫", "inland_flood"),
]

SNAP_WARN_DIST_M = 200.0


def ensure_input_csv(input_path: Path) -> Path:
    """入力CSVが無ければ全国版をDLして江戸川区分を抽出する"""
    if input_path.exists():
        logger.info("入力CSVを使用: %s", input_path)
        return input_path
    logger.info("入力CSVが無いため全国版をダウンロード: %s", NATIONAL_CSV_URL)
    national_path = RAW_DIR / "mergeFromCity_2.csv"
    if not national_path.exists():
        RAW_DIR.mkdir(parents=True, exist_ok=True)
        resp = requests.get(NATIONAL_CSV_URL, timeout=120)
        resp.raise_for_status()
        national_path.write_bytes(resp.content)
    national = pd.read_csv(national_path, encoding="utf-8-sig", dtype=str, keep_default_na=False)
    edogawa = national[national[COL_MUNICIPALITY] == MUNICIPALITY]
    if len(edogawa) == 0:
        raise RuntimeError(f"全国版CSVに {MUNICIPALITY} の行が無い")
    input_path.parent.mkdir(parents=True, exist_ok=True)
    edogawa.to_csv(input_path, index=False, encoding="utf-8-sig")
    logger.info("江戸川区分 %d 行を抽出 → %s", len(edogawa), input_path)
    return input_path


def _truthy(value: str) -> bool:
    return str(value).strip() not in ("", "0")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=RAW_DIR / "shelters_edogawa.csv")
    args = parser.parse_args()

    csv_path = ensure_input_csv(args.input)
    df = pd.read_csv(csv_path, encoding="utf-8-sig", dtype=str, keep_default_na=False)

    required = [COL_ID, COL_MUNICIPALITY, COL_NAME, COL_LAT, COL_LON] + [c for c, _ in TYPE_COLUMNS]
    missing_cols = [c for c in required if c not in df.columns]
    if missing_cols:
        raise RuntimeError(f"入力CSVに必要な列が無い: {missing_cols}")

    df = df[df[COL_MUNICIPALITY] == MUNICIPALITY].copy()
    logger.info("避難所 %d 行を処理", len(df))

    # 近接判定用ツリー (§6.2 水域 / 全ノード)
    water_tree = build_graph.load_water_tree()
    nodes = pd.read_parquet(NODES_PARQUET)
    node_x, node_y = TO_PLANE.transform(nodes["lon"].to_numpy(), nodes["lat"].to_numpy())
    node_tree = STRtree([Point(x, y) for x, y in zip(node_x, node_y)])
    node_ids = nodes["id"].to_numpy()

    records = []
    seen_ids = set()
    for seq, row in enumerate(df.to_dict("records"), start=1):
        shelter_id = str(row[COL_ID]).strip()
        if not shelter_id:
            shelter_id = f"koto-{seq:04d}"  # 元データにIDが無い場合の採番 (§2)
        if shelter_id in seen_ids:
            logger.warning("重複 shelter_id をスキップ: %s (%s)", shelter_id, row[COL_NAME])
            continue
        seen_ids.add(shelter_id)

        lat, lon = float(row[COL_LAT]), float(row[COL_LON])
        types = ",".join(vocab for col, vocab in TYPE_COLUMNS if _truthy(row[col]))
        if not types:
            logger.warning("対応災害種別が空: %s (%s)", shelter_id, row[COL_NAME])

        elevation = get_elevation(lat, lon)
        if elevation is None:
            logger.warning("標高欠測: %s (%s) → 0.0", shelter_id, row[COL_NAME])
            elevation = 0.0

        x, y = TO_PLANE.transform(lon, lat)
        point = Point(x, y)
        coast_dist = min(
            float(water_tree.query_nearest(point, return_distance=True, all_matches=False)[1][0]),
            WATER_DIST_CLIP_M,
        )
        nn_idx, nn_dist = node_tree.query_nearest(point, return_distance=True, all_matches=False)
        nearest_node = int(node_ids[int(nn_idx[0])])
        if float(nn_dist[0]) > SNAP_WARN_DIST_M:
            logger.warning(
                "スナップ距離 %.1fm > %.0fm: %s (%s)",
                float(nn_dist[0]), SNAP_WARN_DIST_M, shelter_id, row[COL_NAME],
            )

        records.append(
            {
                "shelter_id": shelter_id,
                "name": str(row[COL_NAME]).strip(),
                "lat": lat,
                "lon": lon,
                "elevation_m": float(elevation),
                "coast_distance_m": coast_dist,
                "types": types,
                "capacity": 0,  # 元データに収容人数が無いため 0 (§6.3)
                "nearest_node": nearest_node,
            }
        )

    shelters = pd.DataFrame(records)
    if len(shelters) == 0:
        raise RuntimeError("避難所が0件")
    shelters.to_parquet(SHELTERS_PARQUET, index=False)
    logger.info("04 完了: shelters=%d", len(shelters))
    return 0


if __name__ == "__main__":
    sys.exit(main())
