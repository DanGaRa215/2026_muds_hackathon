"""01: OSM道路網・水域の取得 → 中間ファイル (仕様書§6.1, §6.2の取得部分)

- 対象範囲: 東京23区行政界 + 1.5km バッファ (§3)。行政界が取れない場合は bbox。
- 道路網: network_type="walk"。walkフィルタに加えて
  highway in (motorway, motorway_link, trunk, trunk_link) / access=private / foot=no
  を明示的に除外し、simplify を適用して GraphML に保存。
- 水域: waterway=* / natural=water / landuse=basin / natural=coastline の和集合を
  features として取得し GeoJSON に保存。
"""

from __future__ import annotations

import datetime
import sys
import time

import geopandas as gpd
import osmnx as ox
from shapely.geometry import box

from pipeline_common import (
    BOUNDARY_GEOJSON,
    BUFFER_M,
    FALLBACK_BBOX,
    FETCH_INFO_JSON,
    GRAPH_GRAPHML,
    INTERIM_DIR,
    OVERPASS_URL,
    TOKYO23_WARDS,
    WATER_GEOJSON,
    setup_logging,
    write_json,
)

logger = setup_logging("01_fetch_osm")

EXCLUDED_HIGHWAYS = {"motorway", "motorway_link", "trunk", "trunk_link"}
WATER_TAGS = {
    "waterway": True,
    "natural": ["water", "coastline"],
    "landuse": ["basin"],
}
WATER_GEOM_TYPES = {"LineString", "MultiLineString", "Polygon", "MultiPolygon"}


def _configure_osmnx() -> None:
    ox.settings.overpass_url = OVERPASS_URL
    ox.settings.use_cache = True
    ox.settings.cache_folder = INTERIM_DIR / "osmnx_cache"
    ox.settings.requests_timeout = 300
    ox.settings.log_console = False


def _retry(func, what: str, attempts: int = 3, wait_s: float = 15.0):
    for attempt in range(1, attempts + 1):
        try:
            return func()
        except Exception as e:
            logger.warning("%s に失敗 (attempt %d/%d): %s", what, attempt, attempts, e)
            if attempt == attempts:
                raise
            time.sleep(wait_s * attempt)


def _get_boundary() -> tuple[gpd.GeoDataFrame, str]:
    """東京23区の行政界union。取得失敗時は§3のbboxにフォールバック。"""
    try:
        queries = [f"{ward}, 東京都, 日本" for ward in TOKYO23_WARDS]
        gdf = _retry(
            lambda: ox.geocode_to_gdf(queries),
            "行政界ジオコーディング",
        )
        gdf = gdf[gdf.geometry.geom_type.isin(["Polygon", "MultiPolygon"])]
        if len(gdf) == len(TOKYO23_WARDS):
            geom = gdf.geometry.union_all()
            logger.info("東京23区行政界ポリゴンを取得 (Nominatim)")
            return gpd.GeoDataFrame(geometry=[geom], crs=gdf.crs)[["geometry"]], (
                "nominatim(東京23区行政界union)"
            )
        geom = gdf.geometry.union_all() if len(gdf) else None
        if geom.geom_type in ("Polygon", "MultiPolygon"):
            logger.warning("行政界取得が一部欠落 (%d/%d)。取得分のunionを使用", len(gdf), len(TOKYO23_WARDS))
            return gpd.GeoDataFrame(geometry=[geom], crs=gdf.crs)[["geometry"]], (
                f"nominatim(東京23区行政界partial {len(gdf)}/{len(TOKYO23_WARDS)})"
            )
        logger.warning("ジオコーディング結果がポリゴンでない")
    except Exception as e:
        logger.warning("行政界の取得に失敗: %s", e)
    logger.warning("フォールバック bbox を使用: %s", FALLBACK_BBOX)
    bbox_geom = box(
        FALLBACK_BBOX["lon_min"],
        FALLBACK_BBOX["lat_min"],
        FALLBACK_BBOX["lon_max"],
        FALLBACK_BBOX["lat_max"],
    )
    return gpd.GeoDataFrame(geometry=[bbox_geom], crs="EPSG:4326"), "fallback_bbox"


def _buffered_polygon(boundary: gpd.GeoDataFrame):
    """行政界 + 1.5km バッファ (EPSG:6677 でバッファし WGS84 へ戻す)"""
    buffered = boundary.to_crs("EPSG:6677").buffer(BUFFER_M).to_crs("EPSG:4326")
    return buffered.union_all()


def _tag_matches(value, targets: set[str]) -> bool:
    if value is None:
        return False
    values = value if isinstance(value, list) else [value]
    return any(v in targets for v in values)


def _fetch_graph(polygon):
    logger.info("Overpass から歩行者ネットワークを取得中 (simplify前)...")
    graph = _retry(
        lambda: ox.graph_from_polygon(
            polygon,
            network_type="walk",
            simplify=False,
            retain_all=True,
            truncate_by_edge=True,
        ),
        "道路網の取得",
    )
    logger.info("取得完了: %d nodes / %d edges (未簡略化)", len(graph.nodes), len(graph.edges))

    # §6.1 明示的な除外
    to_remove = []
    for u, v, k, data in graph.edges(keys=True, data=True):
        if (
            _tag_matches(data.get("highway"), EXCLUDED_HIGHWAYS)
            or _tag_matches(data.get("access"), {"private"})
            or _tag_matches(data.get("foot"), {"no"})
        ):
            to_remove.append((u, v, k))
    graph.remove_edges_from(to_remove)
    isolated = [n for n, deg in graph.degree() if deg == 0]
    graph.remove_nodes_from(isolated)
    logger.info("除外: %d edges, 孤立 %d nodes を削除", len(to_remove), len(isolated))

    graph = ox.simplify_graph(graph)
    logger.info("簡略化後: %d nodes / %d edges", len(graph.nodes), len(graph.edges))
    return graph


def _fetch_water(polygon) -> gpd.GeoDataFrame:
    logger.info("水域フィーチャを取得中...")
    gdf = _retry(
        lambda: ox.features_from_polygon(polygon, tags=WATER_TAGS),
        "水域の取得",
    )
    gdf = gdf[gdf.geometry.geom_type.isin(WATER_GEOM_TYPES)][["geometry"]]
    gdf = gdf.reset_index(drop=True)
    if len(gdf) == 0:
        # §6.2 水域ゼロはデータ取得失敗を意味するため停止
        raise RuntimeError("水域ジオメトリが0件。東京23区で水域ゼロはあり得ないため停止")
    logger.info("水域: %d ジオメトリ", len(gdf))
    return gdf


def main() -> int:
    force = "--force" in sys.argv
    outputs = [BOUNDARY_GEOJSON, GRAPH_GRAPHML, WATER_GEOJSON, FETCH_INFO_JSON]
    if not force and all(p.exists() for p in outputs):
        logger.info("中間ファイルが揃っているため取得をスキップ (--force で再取得)")
        return 0

    INTERIM_DIR.mkdir(parents=True, exist_ok=True)
    _configure_osmnx()

    boundary, boundary_source = _get_boundary()
    polygon = _buffered_polygon(boundary)
    buffered_gdf = gpd.GeoDataFrame(geometry=[polygon], crs="EPSG:4326")
    BOUNDARY_GEOJSON.unlink(missing_ok=True)
    buffered_gdf.to_file(BOUNDARY_GEOJSON, driver="GeoJSON")

    graph = _fetch_graph(polygon)
    ox.save_graphml(graph, filepath=GRAPH_GRAPHML)

    water = _fetch_water(polygon)
    WATER_GEOJSON.unlink(missing_ok=True)
    water.to_file(WATER_GEOJSON, driver="GeoJSON")

    lon_min, lat_min, lon_max, lat_max = polygon.bounds
    write_json(
        FETCH_INFO_JSON,
        {
            "fetched_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "overpass_url": OVERPASS_URL,
            "osmnx_version": ox.__version__,
            "network_type": "walk",
            "boundary_source": boundary_source,
            "buffer_m": BUFFER_M,
            "bbox": {
                "lat_min": round(lat_min, 6),
                "lon_min": round(lon_min, 6),
                "lat_max": round(lat_max, 6),
                "lon_max": round(lon_max, 6),
            },
        },
    )
    logger.info("01 完了")
    return 0


if __name__ == "__main__":
    sys.exit(main())
