"""05: SQLite出力と検証 (仕様書§6.5, §7)

- スキーマは仕様書§2 の SQL をそのまま使用(変更禁止)
- 全insertは単一トランザクション。書き込み後 VACUUM / ANALYZE
- §7 受け入れ条件 1〜8 を自動チェックし、1つでも失敗したら非0で終了 (§7.9)
- 検証実測値は output/verification.json にも書き出す (README 記録用)
- --verify-only: 既存DBの検証のみ実行
"""

from __future__ import annotations

import datetime
import json
import sqlite3
import sys

import networkx as nx
import pandas as pd
from shapely.geometry import Point
from shapely.strtree import STRtree

from pipeline_common import (
    DB_PATH,
    EDGES_ELEV_PARQUET,
    FETCH_INFO_JSON,
    NODES_PARQUET,
    OUTPUT_DIR,
    SHELTERS_PARQUET,
    TO_PLANE,
    VERIFICATION_JSON,
    read_json,
    setup_logging,
)

logger = setup_logging("05_write_db")

SCHEMA_SQL = """
CREATE TABLE nodes (
  id INTEGER PRIMARY KEY,          -- OSM node id をそのまま使用
  lat REAL NOT NULL,               -- WGS84 十進度
  lon REAL NOT NULL
);

CREATE TABLE edges (
  id INTEGER PRIMARY KEY,          -- 連番でよい
  from_node INTEGER NOT NULL REFERENCES nodes(id),
  to_node INTEGER NOT NULL REFERENCES nodes(id),
  length_m REAL NOT NULL,          -- 道なり実距離(m)。投影座標系で計算
  is_bridge INTEGER NOT NULL DEFAULT 0,   -- OSM bridge=* (bridge=no除く)
  is_tunnel INTEGER NOT NULL DEFAULT 0,   -- OSM tunnel=* (tunnel=no除く)。アンダーパス含む
  water_dist_m REAL,               -- エッジ中点から最寄り水域までの距離(m)
  elevation_m REAL,                -- エッジ中点の標高(m)
  geometry TEXT NOT NULL           -- 描画用座標列 [[lat,lon],[lat,lon],...] のJSON文字列
);
CREATE INDEX idx_edges_from ON edges(from_node);
CREATE INDEX idx_edges_to ON edges(to_node);

CREATE TABLE shelters (
  shelter_id TEXT PRIMARY KEY,     -- 元データの施設ID。無ければ 'koto-0001' 形式で採番
  name TEXT NOT NULL,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  elevation_m REAL NOT NULL,
  coast_distance_m REAL NOT NULL,  -- 最寄り水域までの距離(m)。列名は既存Dartモデル都合
  types TEXT NOT NULL,             -- 対応災害種別CSV。語彙は §6.3
  capacity INTEGER NOT NULL,       -- 不明なら 0
  nearest_node INTEGER NOT NULL REFERENCES nodes(id)
);

CREATE TABLE meta (                -- 生成情報(デバッグ用)
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
"""

# §7.7 検証探索の駅座標
STATIONS = {
    "西葛西駅": (35.6647, 139.8586),
    "船堀駅": (35.6837, 139.8646),
}
ROUTING_SHELTER_TYPES = {"earthquake", "fire", "flood", "surge"}


def build_db() -> None:
    nodes = pd.read_parquet(NODES_PARQUET)
    edges = pd.read_parquet(EDGES_ELEV_PARQUET)
    shelters = pd.read_parquet(SHELTERS_PARQUET)
    fetch_info = read_json(FETCH_INFO_JSON)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    DB_PATH.unlink(missing_ok=True)
    conn = sqlite3.connect(DB_PATH, isolation_level=None)
    try:
        conn.executescript(SCHEMA_SQL)

        # §6.5 単一トランザクションで一括投入
        conn.execute("BEGIN")
        conn.executemany(
            "INSERT INTO nodes (id, lat, lon) VALUES (?, ?, ?)",
            [(int(r.id), float(r.lat), float(r.lon)) for r in nodes.itertuples()],
        )
        conn.executemany(
            "INSERT INTO edges (id, from_node, to_node, length_m, is_bridge, is_tunnel,"
            " water_dist_m, elevation_m, geometry) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                (
                    int(r.id), int(r.from_node), int(r.to_node), float(r.length_m),
                    int(r.is_bridge), int(r.is_tunnel), float(r.water_dist_m),
                    float(r.elevation_m), str(r.geometry),
                )
                for r in edges.itertuples()
            ],
        )
        conn.executemany(
            "INSERT INTO shelters (shelter_id, name, lat, lon, elevation_m,"
            " coast_distance_m, types, capacity, nearest_node)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                (
                    str(r.shelter_id), str(r.name), float(r.lat), float(r.lon),
                    float(r.elevation_m), float(r.coast_distance_m), str(r.types),
                    int(r.capacity), int(r.nearest_node),
                )
                for r in shelters.itertuples()
            ],
        )
        osm_source = (
            f"OpenStreetMap via Overpass ({fetch_info['overpass_url']}), "
            f"osmnx {fetch_info['osmnx_version']}, network_type=walk, "
            f"fetched_at={fetch_info['fetched_at']}"
        )
        meta_rows = [
            ("generated_at", datetime.datetime.now(datetime.timezone.utc).isoformat()),
            ("osm_source", osm_source),
            ("bbox", json.dumps(fetch_info["bbox"])),
            ("node_count", str(len(nodes))),
            ("edge_count", str(len(edges))),
        ]
        conn.executemany("INSERT INTO meta (key, value) VALUES (?, ?)", meta_rows)
        conn.execute("COMMIT")

        conn.execute("VACUUM")
        conn.execute("ANALYZE")
    finally:
        conn.close()
    logger.info("routing.db 書き込み完了: %s", DB_PATH)


def verify() -> bool:
    """§7 受け入れ条件 1〜8 の自動チェック。結果を verification.json に書く。"""
    conn = sqlite3.connect(DB_PATH)
    checks = []

    def add(no, name, passed, measured, criterion):
        checks.append(
            {"no": no, "name": name, "passed": bool(passed),
             "measured": measured, "criterion": criterion}
        )

    # 1. 件数オーダー
    node_count = conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
    edge_count = conn.execute("SELECT COUNT(*) FROM edges").fetchone()[0]
    add(1, "nodes/edges 件数",
        8_000 <= node_count <= 80_000 and 10_000 <= edge_count <= 120_000,
        f"nodes={node_count:,}, edges={edge_count:,}",
        "nodes 8,000〜80,000 / edges 10,000〜120,000")

    # 2. 単一連結成分
    edge_rows = conn.execute("SELECT from_node, to_node, length_m FROM edges").fetchall()
    node_ids = {row[0] for row in conn.execute("SELECT id FROM nodes")}
    graph = nx.MultiGraph()
    graph.add_nodes_from(node_ids)
    graph.add_weighted_edges_from(edge_rows, weight="length_m")
    n_components = nx.number_connected_components(graph)
    endpoints_ok = all(u in node_ids and v in node_ids for u, v, _ in edge_rows)
    add(2, "単一連結成分",
        n_components == 1 and endpoints_ok,
        f"連結成分数={n_components}, エッジ端点の実在={'OK' if endpoints_ok else 'NG'}",
        "連結成分数=1")

    # 3. water_dist_m
    water_null = conn.execute("SELECT COUNT(*) FROM edges WHERE water_dist_m IS NULL").fetchone()[0]
    water_near = conn.execute("SELECT COUNT(*) FROM edges WHERE water_dist_m < 300").fetchone()[0]
    near_ratio = water_near / edge_count if edge_count else 0.0
    add(3, "water_dist_m NULL=0 かつ <300m 比率≥15%",
        water_null == 0 and near_ratio >= 0.15,
        f"NULL={water_null}, <300m: {water_near:,}/{edge_count:,} = {near_ratio:.1%}",
        "NULL=0 / 比率≥15%")

    # 4. elevation_m (「概ね収まる」は 95% 以上が範囲内、と定義して判定)
    elev_null = conn.execute("SELECT COUNT(*) FROM edges WHERE elevation_m IS NULL").fetchone()[0]
    elev_min, elev_max = conn.execute("SELECT MIN(elevation_m), MAX(elevation_m) FROM edges").fetchone()
    in_range = conn.execute(
        "SELECT COUNT(*) FROM edges WHERE elevation_m BETWEEN -5.0 AND 15.0"
    ).fetchone()[0]
    in_ratio = in_range / edge_count if edge_count else 0.0
    add(4, "elevation_m NULL=0 かつ値域 -5〜+15m に概ね収まる",
        elev_null == 0 and in_ratio >= 0.95,
        f"NULL={elev_null}, min={elev_min:.2f}m, max={elev_max:.2f}m, 範囲内={in_ratio:.1%}",
        "NULL=0 / -5.0〜+15.0m 内が95%以上")

    # 5. 橋エッジ数
    bridge_count = conn.execute("SELECT COUNT(*) FROM edges WHERE is_bridge = 1").fetchone()[0]
    add(5, "is_bridge=1 が50本以上", bridge_count >= 50,
        f"is_bridge=1: {bridge_count:,}本", "≥50本")

    # 6. shelters
    shelter_count = conn.execute("SELECT COUNT(*) FROM shelters").fetchone()[0]
    orphan = conn.execute(
        "SELECT COUNT(*) FROM shelters s LEFT JOIN nodes n ON s.nearest_node = n.id"
        " WHERE n.id IS NULL"
    ).fetchone()[0]
    add(6, "shelters ≥10件 かつ nearest_node 実在",
        shelter_count >= 10 and orphan == 0,
        f"shelters={shelter_count}, nearest_node不整合={orphan}",
        "≥10件 / JOIN不整合=0")

    type_rows = [row[0] for row in conn.execute("SELECT types FROM shelters")]
    empty_types = sum(1 for value in type_rows if not str(value).strip())
    invalid_tokens = sorted({
        token
        for value in type_rows
        for token in str(value).split(",")
        if token.strip() and token.strip() not in ROUTING_SHELTER_TYPES
    })
    flood_surge = conn.execute(
        "SELECT COUNT(*) FROM shelters"
        " WHERE types LIKE '%flood%' OR types LIKE '%surge%'"
    ).fetchone()[0]
    distribution = conn.execute(
        "SELECT types, COUNT(*) FROM shelters GROUP BY types ORDER BY types"
    ).fetchall()
    distribution_text = ", ".join(f"{types or '(empty)'}:{count}" for types, count in distribution)
    add(7, "shelters.types がrouting語彙と整合",
        empty_types == 0 and not invalid_tokens,
        f"empty={empty_types}, invalid={invalid_tokens or 'なし'}, "
        f"flood/surge={flood_surge}, distribution={distribution_text}",
        "empty=0 / 語彙は earthquake,fire,flood,surge のみ。flood/surge=0は該当なし")

    # 8. 検証探索 (西葛西駅〜船堀駅)
    node_rows = conn.execute("SELECT id, lat, lon FROM nodes").fetchall()
    xs, ys = TO_PLANE.transform([r[2] for r in node_rows], [r[1] for r in node_rows])
    tree = STRtree([Point(x, y) for x, y in zip(xs, ys)])
    station_nodes = {}
    for name, (lat, lon) in STATIONS.items():
        sx, sy = TO_PLANE.transform(lon, lat)
        idx, _dist = tree.query_nearest(Point(sx, sy), return_distance=True, all_matches=False)
        station_nodes[name] = node_rows[int(idx[0])][0]
    try:
        path_len = nx.shortest_path_length(
            graph, station_nodes["西葛西駅"], station_nodes["船堀駅"], weight="length_m"
        )
        path_ok = 1_500.0 <= path_len <= 6_000.0
        measured = f"経路長={path_len:,.0f}m (nodes {station_nodes['西葛西駅']}→{station_nodes['船堀駅']})"
    except nx.NetworkXNoPath:
        path_ok, measured = False, "経路なし"
    add(8, "西葛西駅〜船堀駅の最短経路 1.5〜6.0km", path_ok, measured, "1,500〜6,000m")

    # 9. ファイルサイズ
    size_bytes = DB_PATH.stat().st_size
    size_mb = size_bytes / (1024 * 1024)
    add(9, "routing.db ≤80MB", size_bytes <= 80 * 1024 * 1024,
        f"{size_mb:.1f}MB ({size_bytes:,} bytes)", "≤80MB")

    conn.close()

    all_passed = all(c["passed"] for c in checks)
    report = {
        "verified_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "db_path": str(DB_PATH),
        "db_size_bytes": size_bytes,
        "all_passed": all_passed,
        "checks": checks,
    }
    VERIFICATION_JSON.parent.mkdir(parents=True, exist_ok=True)
    VERIFICATION_JSON.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    for c in checks:
        logger.info(
            "[%s] §7-%d %s: %s (基準: %s)",
            "PASS" if c["passed"] else "FAIL", c["no"], c["name"], c["measured"], c["criterion"],
        )
    logger.info("受け入れ条件: %s", "全て合格" if all_passed else "不合格あり")
    return all_passed


def main() -> int:
    if "--verify-only" not in sys.argv:
        build_db()
    if not DB_PATH.exists():
        logger.error("routing.db が存在しない: %s", DB_PATH)
        return 1
    return 0 if verify() else 1  # §7.9 検証失敗は非0終了


if __name__ == "__main__":
    sys.exit(main())
