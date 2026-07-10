# preprocess — routing.db 生成スクリプト

仕様書①(`specification/spec01_preprocessing_python.md`)に基づく前処理パイプライン。
東京23区+バッファ1.5kmの歩行者ルーティンググラフ・避難所・水域距離・標高を
SQLite 単一ファイル `output/routing.db` に焼く。

- DBには生の事実のみを格納する。危険度コスト計算はアプリ側(Dart)の責務
- エッジは無向で1行のみ格納。双方向展開はアプリ側の責務
- 距離計算・近接判定はすべて JGD2011 平面直角座標系 第IX系 (EPSG:6677)

## セットアップと実行

```bash
cd preprocess
python3.12 -m venv .venv          # Python 3.11+
.venv/bin/pip install -r requirements.txt
.venv/bin/python run_all.py --force --geom-decimals 5  # 01〜05 を順次実行し §7 を自動検証
```

- `run_all.py --force` で OSM の再取得を強制
- `run_all.py --geom-decimals 5` で geometry 座標丸めを5桁に(23区版assetサイズ抑制)
- 各ステップは中間ファイル(`data/interim/`)経由で疎結合。個別再実行も可

## パイプライン構成

| スクリプト | 役割 |
|---|---|
| `01_fetch_osm.py` | OSM道路網(walk)・水域の取得 → GraphML / GeoJSON |
| `02_build_graph.py` | 無向化・最大連結成分・length_m/橋/トンネル/水域距離の付与 |
| `03_fetch_elevation.py` | エッジ中点の標高付与(国土地理院 標高タイル) |
| `04_build_shelters.py` | 避難所の取り込み・types変換・標高/水域距離/最近傍ノード |
| `05_write_db.py` | SQLite出力(単一トランザクション、VACUUM/ANALYZE)と§7検証 |
| `run_all.py` | 上記を順次実行し、検証結果を本READMEへ自動記録 |
| `pipeline_common.py` / `elevation_util.py` | 共通定数・座標変換・標高タイル取得 |

## データソースと取得手順

### OSM 道路網・水域

- Overpass API 経由(osmnx)。本家 `overpass-api.de` は本環境から HTTP 406 を
  返したため、公式ミラー `https://lz4.overpass-api.de/api` を使用(データは同一)
- 行政界は Nominatim で東京23区各区をジオコーディングし、union して使う。
  取得不可時は仕様書§3の bbox にフォールバック

### 避難所(国土地理院 指定緊急避難場所データ)

- 入力: 既定では `../bosai_app/assets/shelters.db` のGSIスナップショットから
  `city_code IN 13101..13123` の2,179件を抽出する
- `shelters.db` が無い生成環境では、`data/raw/shelters_tokyo23.csv`
  (`--input` で変更可) にフォールバックする
- CSVも無い場合は全国版CSVを自動ダウンロードして東京23区分を抽出する:
  1. 配布元: 国土地理院「指定緊急避難場所データ」
     https://hinanmap.gsi.go.jp/hinanjocp/hinanbasho/koukaidate.html
  2. 全国版CSV(指定緊急避難場所・災害種別フラグ付き):
     https://hinanmap.gsi.go.jp/hinanjocp/defaultFtpData/csv/mergeFromCity_2.csv
  3. 「都道府県名及び市町村名」列が `東京都{23区名}` の行を抽出し
     `data/raw/shelters_tokyo23.csv` に保存(UTF-8 BOM付き)
- routing.db の `types` 語彙は Dart 側 `DisasterMode` に合わせて4種に限定する:
  地震→`earthquake` / 大規模な火事→`fire` / 洪水→`flood` / 高潮→`surge`
- 23区2,179件のうち、4種別に該当しない `types` 空行は1,220件。
  アプリ側ではラベル未整備として表示し、近傍候補からは除外しない
- `capacity` が NULL の場合は -1 として `routing.db` に格納し、UIでは「不明」と表示する

### 標高(国土地理院 標高タイル)

- 一次: `dem5a` (zoom 15)。欠測セル・欠測タイルは DEM10B でフォールバック
- DEM10B のテキストタイルIDは `dem`(zoom 14)。`dem10b` というIDの
  テキストタイルは存在しない(HTTP 404 確認済み)
- タイルは `data/interim/dem/` にキャッシュ。リクエスト間隔 0.1s 以上

## 検証の実装メモ

- §7 の 1〜9 は `05_write_db.py` の `verify()` が生成後の `routing.db` 自体を
  読み取って判定し、1つでも失敗すると非0で終了する(§7.9)
- §7.4 の「値域が -5.0〜+70.0 m に概ね収まる」は「範囲内が95%以上」と定義して判定
  (実測の min/max/範囲内比率を下表に記録)

## 受け入れ条件 検証結果 (§7)

<!-- ACCEPTANCE_RESULTS:BEGIN -->

- 検証日時: 2026-07-10T01:39:16.466656+00:00
- DB: `/Users/reo_huk/2026muds/2026_muds_hackathon/preprocess/output/routing.db` (108.6 MB)
- 総合判定: **全て合格**

| # | 受け入れ条件 | 基準 | 実測値 | 判定 |
|---|---|---|---|---|
| 1 | nodes/edges 件数 | nodes 150,000〜800,000 / edges 200,000〜1,200,000 | nodes=479,627, edges=703,264 | ✅ PASS |
| 2 | 単一連結成分 | 連結成分数=1 | 連結成分数=1, エッジ端点の実在=OK | ✅ PASS |
| 3 | water_dist_m NULL=0 かつ <300m 比率≥5% | NULL=0 / 比率≥5% | NULL=0, <300m: 392,676/703,264 = 55.8% | ✅ PASS |
| 4 | elevation_m NULL=0 かつ値域 -5〜+70m に概ね収まる | NULL=0 / -5.0〜+70.0m 内が95%以上 | NULL=0, min=-10.86m, max=65.11m, 範囲内=100.0% | ✅ PASS |
| 5 | is_bridge=1 が500本以上 | ≥500本 | is_bridge=1: 8,399本 | ✅ PASS |
| 6 | shelters ≥2,000件 かつ nearest_node 実在 | ≥2,000件 / JOIN不整合=0 | shelters=2179, nearest_node不整合=0 | ✅ PASS |
| 7 | shelters.types がrouting語彙と整合 | 語彙は earthquake,fire,flood,surge のみ / 種別付き・flood/surge が1件以上 | empty=1220, invalid=なし, flood/surge=673, distribution=(empty):1220, earthquake:178, earthquake,fire:104, earthquake,fire,flood:116, earthquake,flood:131, earthquake,flood,surge:85, earthquake,surge:18, fire:4, flood:136, flood,surge:187 | ✅ PASS |
| 8 | 東西2系統の最短経路が妥当 | 西葛西〜船堀 1,500〜6,000m / 三軒茶屋〜新宿 4,000〜10,000m | 西葛西駅〜船堀駅: 2,507m (nodes 6183709275→4210150308) / 三軒茶屋駅〜新宿駅: 6,966m (nodes 8367910234→11965354256) | ✅ PASS |
| 9 | routing.db ≤200MB | ≤200MB | 108.6MB (113,889,280 bytes) | ✅ PASS |

<!-- ACCEPTANCE_RESULTS:END -->

## 将来課題

- ハザードマップポリゴン(津波・洪水浸水想定)・液状化予測図の取り込みは将来拡張(スコープ外)
