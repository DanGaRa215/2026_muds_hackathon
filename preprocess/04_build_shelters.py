"""04: 避難所の取り込みとスナップ (仕様書§6.3)

- 入力: 既定では bosai_app/assets/shelters.db のGSIスナップショットから
  東京23区(13101〜13123)を抽出する
- shelters.db が無い環境では、国土地理院「指定緊急避難場所データ」の
  東京23区分CSV (data/raw/shelters_tokyo23.csv) にフォールバックする
- routing.db の types 語彙: earthquake, fire, flood, surge
- elevation_m: §6.4 と同じ方法 / coast_distance_m: §6.2 と同じ STRtree
- nearest_node: ノードSTRtree で最近傍。200m超は警告ログ
"""

from __future__ import annotations

import argparse
import importlib
import sqlite3
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
    TOKYO23_CITY_CODES,
    TOKYO23_WARDS,
    WATER_DIST_CLIP_M,
    setup_logging,
)

logger = setup_logging("04_build_shelters")

# 02_build_graph.py の水域STRtree構築を再利用 (ファイル名が数字始まりのため importlib)
build_graph = importlib.import_module("02_build_graph")

# 国土地理院 指定緊急避難場所データ(全国版CSV)。README に手順を記載
NATIONAL_CSV_URL = "https://hinanmap.gsi.go.jp/hinanjocp/defaultFtpData/csv/mergeFromCity_2.csv"
TOKYO23_MUNICIPALITIES = [f"東京都{ward}" for ward in TOKYO23_WARDS]
DEFAULT_GSI_DB = Path(__file__).resolve().parents[1] / "bosai_app" / "assets" / "shelters.db"

COL_ID = "共通ID"
COL_MUNICIPALITY = "都道府県名及び市町村名"
COL_NAME = "施設・場所名"
COL_LAT = "緯度"
COL_LON = "経度"

# routing.db が扱う災害種別語彙。Dart 側 DisasterMode と同じ4語に限定する。
TYPE_COLUMNS = [
    ("地震", "earthquake"),
    ("大規模な火事", "fire"),
    ("洪水", "flood"),
    ("高潮", "surge"),
]
GSI_TYPE_COLUMNS = [
    ("t_earthquake", "earthquake"),
    ("t_fire", "fire"),
    ("t_flood", "flood"),
    ("t_storm_surge", "surge"),
]

SNAP_WARN_DIST_M = 200.0


def ensure_input_csv(input_path: Path) -> Path:
    """入力CSVが無ければ全国版をDLして東京23区分を抽出する"""
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
    tokyo23 = national[national[COL_MUNICIPALITY].isin(TOKYO23_MUNICIPALITIES)]
    if len(tokyo23) == 0:
        raise RuntimeError("全国版CSVに東京23区の行が無い")
    input_path.parent.mkdir(parents=True, exist_ok=True)
    tokyo23.to_csv(input_path, index=False, encoding="utf-8-sig")
    logger.info("東京23区分 %d 行を抽出 → %s", len(tokyo23), input_path)
    return input_path


def _truthy(value: str) -> bool:
    return str(value).strip() not in ("", "0")


def _types_from_gsi_row(row: dict) -> str:
    return ",".join(vocab for col, vocab in GSI_TYPE_COLUMNS if _truthy(row[col]))


def _types_from_csv_row(row: dict) -> str:
    return ",".join(vocab for col, vocab in TYPE_COLUMNS if _truthy(row[col]))


def load_shelter_rows(input_path: Path, gsi_db_path: Path) -> tuple[list[dict], str]:
    """GSIスナップショットDBがあれば正として使い、無ければ従来CSVを使う。"""
    if gsi_db_path.exists():
        logger.info("GSI shelters.db から東京23区を抽出: %s", gsi_db_path)
        with sqlite3.connect(gsi_db_path) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute(
                """
                SELECT
                  shelter_id, name, lat, lon,
                  t_earthquake, t_fire, t_flood, t_storm_surge,
                  COALESCE(capacity, -1) AS capacity
                FROM shelters
                WHERE city_code IN ({placeholders})
                ORDER BY city_code, name, shelter_id
                """.format(placeholders=",".join("?" for _ in TOKYO23_CITY_CODES)),
                tuple(TOKYO23_CITY_CODES),
            ).fetchall()
        if not rows:
            raise RuntimeError("GSI shelters.db に東京23区(13101〜13123)の行が無い")
        records = []
        for row in rows:
            record = dict(row)
            record["types"] = _types_from_gsi_row(record)
            records.append(record)
        return records, "gsi_db"

    csv_path = ensure_input_csv(input_path)
    df = pd.read_csv(csv_path, encoding="utf-8-sig", dtype=str, keep_default_na=False)

    required = [COL_ID, COL_MUNICIPALITY, COL_NAME, COL_LAT, COL_LON] + [c for c, _ in TYPE_COLUMNS]
    missing_cols = [c for c in required if c not in df.columns]
    if missing_cols:
        raise RuntimeError(f"入力CSVに必要な列が無い: {missing_cols}")

    df = df[df[COL_MUNICIPALITY].isin(TOKYO23_MUNICIPALITIES)].copy()
    records = []
    for seq, row in enumerate(df.to_dict("records"), start=1):
        shelter_id = str(row[COL_ID]).strip()
        if not shelter_id:
            shelter_id = f"tokyo23-{seq:04d}"  # 元データにIDが無い場合の採番 (§2)
        records.append(
            {
                "shelter_id": shelter_id,
                "name": str(row[COL_NAME]).strip(),
                "lat": float(row[COL_LAT]),
                "lon": float(row[COL_LON]),
                "types": _types_from_csv_row(row),
                "capacity": -1,
            }
        )
    return records, "csv"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=RAW_DIR / "shelters_tokyo23.csv")
    parser.add_argument("--gsi-db", type=Path, default=DEFAULT_GSI_DB)
    args = parser.parse_args()

    source_rows, source = load_shelter_rows(args.input, args.gsi_db)
    logger.info("避難所 %d 行を処理 (source=%s)", len(source_rows), source)

    # 近接判定用ツリー (§6.2 水域 / 全ノード)
    water_tree = build_graph.load_water_tree()
    nodes = pd.read_parquet(NODES_PARQUET)
    node_x, node_y = TO_PLANE.transform(nodes["lon"].to_numpy(), nodes["lat"].to_numpy())
    node_tree = STRtree([Point(x, y) for x, y in zip(node_x, node_y)])
    node_ids = nodes["id"].to_numpy()

    records = []
    seen_ids = set()
    empty_type_count = 0
    for row in source_rows:
        shelter_id = str(row["shelter_id"]).strip()
        if shelter_id in seen_ids:
            logger.warning("重複 shelter_id をスキップ: %s (%s)", shelter_id, row["name"])
            continue
        seen_ids.add(shelter_id)

        lat, lon = float(row["lat"]), float(row["lon"])
        types = str(row["types"])
        if not types:
            empty_type_count += 1

        elevation = get_elevation(lat, lon)
        if elevation is None:
            logger.warning("標高欠測: %s (%s) → 0.0", shelter_id, row["name"])
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
                float(nn_dist[0]), SNAP_WARN_DIST_M, shelter_id, row["name"],
            )

        records.append(
            {
                "shelter_id": shelter_id,
                "name": str(row["name"]).strip(),
                "lat": lat,
                "lon": lon,
                "elevation_m": float(elevation),
                "coast_distance_m": coast_dist,
                "types": types,
                "capacity": int(row.get("capacity") or -1),
                "nearest_node": nearest_node,
            }
        )

    shelters = pd.DataFrame(records)
    if len(shelters) == 0:
        raise RuntimeError("避難所が0件")
    if empty_type_count:
        logger.warning(
            "対応災害種別が空の避難所: %d件 (ラベル未整備として近傍候補には残す)",
            empty_type_count,
        )
    shelters.to_parquet(SHELTERS_PARQUET, index=False)
    logger.info("04 完了: shelters=%d", len(shelters))
    return 0


if __name__ == "__main__":
    sys.exit(main())
