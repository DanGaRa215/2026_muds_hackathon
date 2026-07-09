"""02: ノード/エッジ化、属性付与 (仕様書§6.1, §6.2)

- 無向化して最大連結成分のみ残す
- length_m: EPSG:6677 に投影した線長
- is_bridge / is_tunnel: OSMタグ bridge / tunnel が存在し 'no' 以外なら1
  (simplifyで統合されたエッジは構成wayのいずれかが該当すれば1)
- water_dist_m: エッジ中点(投影座標)から STRtree で最近傍水域までの距離
- geometry: WGS84 の [[lat,lon],...] JSON。小数は既定6桁
  (§7.8 のサイズ超過時は --geom-decimals 5 で再生成する)
"""

from __future__ import annotations

import argparse
import json
import sys

import geopandas as gpd
import networkx as nx
import numpy as np
import osmnx as ox
import pandas as pd
from shapely.geometry import LineString
from shapely.ops import transform as shp_transform
from shapely.strtree import STRtree

from pipeline_common import (
    EDGES_PARQUET,
    GRAPH_GRAPHML,
    NODES_PARQUET,
    TO_PLANE,
    TO_WGS84,
    WATER_DIST_CLIP_M,
    WATER_GEOJSON,
    setup_logging,
)

logger = setup_logging("02_build_graph")


def _flag(value) -> int:
    """bridge/tunnel タグ値 → 0/1。リストは構成wayのいずれか該当で1(安全側)"""
    if value is None:
        return 0
    values = value if isinstance(value, list) else [value]
    return int(any(v not in (None, "no", "") for v in values))


def load_water_tree() -> STRtree:
    """§6.2 水域ジオメトリ(EPSG:6677投影済み)の STRtree"""
    water = gpd.read_file(WATER_GEOJSON)
    if len(water) == 0:
        raise RuntimeError("水域ジオメトリが0件。§6.2 によりエラー停止")
    water_proj = water.to_crs("EPSG:6677")
    return STRtree(list(water_proj.geometry))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--geom-decimals", type=int, default=6)
    args = parser.parse_args()

    logger.info("GraphML 読み込み中...")
    graph = ox.load_graphml(GRAPH_GRAPHML)

    # 無向化 (DBのエッジは無向1行。双方向展開はアプリ側の責務)
    graph_u = ox.convert.to_undirected(graph)

    # §6.1 最大連結成分のみ残す
    components = list(nx.connected_components(graph_u))
    largest = max(components, key=len)
    if len(components) > 1:
        dropped = len(graph_u.nodes) - len(largest)
        logger.info("連結成分 %d 個中、最大成分以外の %d nodes を除去", len(components), dropped)
    graph_u = graph_u.subgraph(largest).copy()
    logger.info("グラフ: %d nodes / %d edges (無向・最大連結成分)", len(graph_u.nodes), len(graph_u.edges))

    # nodes テーブル (OSM node id をそのまま使用)
    nodes = pd.DataFrame(
        [(n, d["y"], d["x"]) for n, d in graph_u.nodes(data=True)],
        columns=["id", "lat", "lon"],
    )

    # edges テーブル
    water_tree = load_water_tree()
    node_xy = {n: (d["x"], d["y"]) for n, d in graph_u.nodes(data=True)}
    records = []
    midpoints = []
    for u, v, _key, data in graph_u.edges(keys=True, data=True):
        geom = data.get("geometry")
        if geom is None:
            geom = LineString([node_xy[u], node_xy[v]])
        geom_proj = shp_transform(TO_PLANE.transform, geom)
        length_m = geom_proj.length
        midpoints.append(geom_proj.interpolate(0.5, normalized=True))
        coords = [
            [round(lat, args.geom_decimals), round(lon, args.geom_decimals)]
            for lon, lat in geom.coords
        ]
        records.append(
            {
                "from_node": u,
                "to_node": v,
                "length_m": length_m,
                "is_bridge": _flag(data.get("bridge")),
                "is_tunnel": _flag(data.get("tunnel")),
                "geometry": json.dumps(coords, separators=(",", ":")),
            }
        )
    edges = pd.DataFrame(records)
    edges.insert(0, "id", range(1, len(edges) + 1))

    # §6.2 エッジ中点から最近傍水域までの距離
    logger.info("水域距離を計算中 (%d edges)...", len(edges))
    indices, distances = water_tree.query_nearest(
        np.array(midpoints, dtype=object), return_distance=True, all_matches=False
    )
    water_dist = np.full(len(midpoints), np.nan)
    water_dist[indices[0]] = distances
    if np.isnan(water_dist).any():
        raise RuntimeError("water_dist_m を計算できないエッジがある (NULL禁止)")
    edges["water_dist_m"] = np.minimum(water_dist, WATER_DIST_CLIP_M)

    # 標高付与(03)用のエッジ中点 (WGS84)
    mid_lon, mid_lat = TO_WGS84.transform(
        np.array([p.x for p in midpoints]), np.array([p.y for p in midpoints])
    )
    edges["mid_lat"] = mid_lat
    edges["mid_lon"] = mid_lon

    nodes.to_parquet(NODES_PARQUET, index=False)
    edges.to_parquet(EDGES_PARQUET, index=False)
    logger.info(
        "02 完了: nodes=%d, edges=%d, water_dist<300m 比率=%.1f%%",
        len(nodes),
        len(edges),
        float((edges["water_dist_m"] < 300).mean() * 100),
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
