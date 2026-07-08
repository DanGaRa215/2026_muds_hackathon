"""国土地理院 標高タイル(テキスト形式)による標高取得 (仕様書§6.4)。

- 一次ソース: dem5a (zoom 15)
- 欠測セル・欠測タイルは DEM10B でフォールバック。
  DEM10B のテキストタイルIDは `dem` (zoom 14)。`dem10b` というIDのタイルは
  存在しない(HTTP 404)ことを確認済み。
- タイルは data/interim/dem/ にキャッシュし、再取得しない。
- ネットワークリクエスト間には 0.1 秒以上のウェイトを入れる。
"""

from __future__ import annotations

import logging
import math
import time

import requests

from pipeline_common import DEM_CACHE_DIR

TILE_URL = "https://cyberjapandata.gsi.go.jp/xyz/{src}/{z}/{x}/{y}.txt"
# (タイルID, zoom) を優先順に試す。dem = DEM10B テキストタイル
DEM_SOURCES = [("dem5a", 15), ("dem", 14)]
REQUEST_WAIT_S = 0.1
TILE_SIZE = 256
MISSING_TILE_MARKER = "__404__"

logger = logging.getLogger(__name__)

_session = requests.Session()
_session.headers["User-Agent"] = "edogawa-offline-routing-preprocess/1.0"
_tile_cache: dict[tuple[str, int, int, int], list[list[float | None]] | None] = {}
_last_request_at = 0.0


def _latlon_to_tile_pixel(lat: float, lon: float, z: int) -> tuple[int, int, int, int]:
    """WGS84座標 -> (タイルx, タイルy, ピクセル列, ピクセル行)"""
    n = 2**z
    xf = (lon + 180.0) / 360.0 * n
    lat_rad = math.radians(lat)
    yf = (1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n
    xtile, ytile = int(xf), int(yf)
    px = min(int((xf - xtile) * TILE_SIZE), TILE_SIZE - 1)
    py = min(int((yf - ytile) * TILE_SIZE), TILE_SIZE - 1)
    return xtile, ytile, px, py


def _fetch_tile_text(src: str, z: int, x: int, y: int) -> str | None:
    """タイル本文を返す。欠測タイル(404)は None。ローカルキャッシュ優先。"""
    global _last_request_at
    cache_path = DEM_CACHE_DIR / src / str(z) / str(x) / f"{y}.txt"
    if cache_path.exists():
        text = cache_path.read_text(encoding="utf-8")
        return None if text == MISSING_TILE_MARKER else text

    # レートリミット: 直前のリクエストから 0.1s 以上空ける
    wait = REQUEST_WAIT_S - (time.monotonic() - _last_request_at)
    if wait > 0:
        time.sleep(wait)

    url = TILE_URL.format(src=src, z=z, x=x, y=y)
    last_err = None
    for attempt in range(3):
        try:
            resp = _session.get(url, timeout=30)
            _last_request_at = time.monotonic()
            if resp.status_code == 404:
                text = None
                break
            resp.raise_for_status()
            text = resp.text
            break
        except requests.RequestException as e:  # リトライ
            last_err = e
            time.sleep(1.0 * (attempt + 1))
    else:
        raise RuntimeError(f"標高タイル取得に3回失敗: {url}: {last_err}")

    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(MISSING_TILE_MARKER if text is None else text, encoding="utf-8")
    return text


def _load_tile(src: str, z: int, x: int, y: int) -> list[list[float | None]] | None:
    """パース済みタイル(256x256、欠測セルは None)。メモリキャッシュ付き。"""
    key = (src, z, x, y)
    if key in _tile_cache:
        return _tile_cache[key]
    text = _fetch_tile_text(src, z, x, y)
    if text is None:
        _tile_cache[key] = None
        return None
    grid: list[list[float | None]] = []
    for line in text.splitlines():
        row = [None if c == "e" or c == "" else float(c) for c in line.split(",")]
        grid.append(row)
    _tile_cache[key] = grid
    return grid


def get_elevation(lat: float, lon: float) -> float | None:
    """標高(m)。dem5a -> dem(DEM10B) の順に引き、全て欠測なら None。"""
    for src, z in DEM_SOURCES:
        x, y, px, py = _latlon_to_tile_pixel(lat, lon, z)
        grid = _load_tile(src, z, x, y)
        if grid is None:
            continue
        try:
            value = grid[py][px]
        except IndexError:
            value = None
        if value is not None:
            return value
    return None
