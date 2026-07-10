# 仕様書① Python前処理スクリプト: routing.db 生成

- 版: v1.0
- 対象: 実装AI(Claude Code / Codex)。本書のみで実装が完結すること
- 成果物: `routing.db`(SQLite単一ファイル)と生成スクリプト一式
- 実行環境: 開発者のPC(macOS)。アプリには**成果物のDBファイルのみ**をassets同梱する

---

## 0. 要確認事項(実装前に人間へ質問すべきこと)

1. 江戸川区の避難所データ(国土地理院 指定緊急避難場所CSV)のダウンロードは実装AIの環境からネットワーク到達できるか。不可なら人間が手動DLして `data/raw/` に置く運用に切り替える(本書はその前提でも動くよう入力ファイルパスを引数化している)
2. 標高タイルの取得(国土地理院サーバ)も同様。到達不可なら人間が対象タイルを事前DLする

上記以外の技術判断は本書で確定済み。**勝手に設計・スキーマを変更しないこと。**

## 1. 背景と目的

東京都江戸川区限定・完全オフラインの避難ルート案内Flutterアプリ(ハッカソン)の第1工程。
OSMの道路網と公的データから、歩行者用ルーティンググラフをSQLiteに焼く。
アプリ側(第2工程のDart実装)はこのDBを読み取り専用で使い、A*探索を行う。

設計思想: **DBには生の事実のみを持たせ、危険度コストの計算はアプリ側で行う。**
したがって本スクリプトはペナルティやコストを一切計算しない。

## 2. 出力スキーマ(確定・変更禁止)

```sql
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
-- edges(from_node/to_node) の検索用indexはアプリ実行時に使わないため作らない。
-- アプリは起動時に edges 全件を読み込み、Dart 側のインメモリグラフで探索する。

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
-- meta には generated_at, osm_source, bbox, node_count, edge_count を入れる
```

注意:
- エッジは**無向**。DBには1行のみ格納し、双方向展開はアプリ側の責務
- 座標は WGS84 の REAL(十進度)で格納。**投影座標をDBに入れない**

## 3. 対象範囲

- 江戸川区の行政界 + **バッファ1.5km**(境界で経路が切れるのを防ぐ。隣接区への橋も含める)
- bbox 目安: lat 35.56〜35.78, lon 139.81〜139.93(行政界ポリゴンが取れない場合のフォールバック)

## 4. 使用ライブラリ(確定)

```
osmnx >= 2.0        # OSM取得・グラフ化
shapely >= 2.0      # ジオメトリ演算・STRtree
pyproj >= 3.6       # 投影変換
pandas
requests
```

Python 3.11+。`requirements.txt` を成果物に含めること。
osmnx 2.x はAPIが1.xと異なる(`ox.graph_from_place` 等のモジュール構成)。実装時にバージョンを確認し、使用バージョンのAPIに合わせること。

## 5. 座標系(確定・重要)

- **距離計算・近接判定はすべて JGD2011 平面直角座標系 第IX系(EPSG:6677)に投影して行う。**
  東京都区部は第IX系。緯度経度のままの距離計算(ユークリッド)は禁止
- pyproj Transformer(EPSG:4326 → EPSG:6677)を1個生成して使い回す
- DB格納・geometry列は WGS84 に戻す

## 6. 処理パイプライン

スクリプトは `preprocess/` ディレクトリに以下の分割で置く(1ファイル巨大化を禁止):

```
preprocess/
  01_fetch_osm.py        # OSM道路網・水域の取得 → 中間ファイル
  02_build_graph.py      # ノード/エッジ化、属性付与(橋・トンネル・水域距離)
  03_fetch_elevation.py  # 標高付与
  04_build_shelters.py   # 避難所の取り込みとスナップ
  05_write_db.py         # SQLite出力と検証
  run_all.py             # 上記を順次実行
  data/raw/              # 手動配置の入力ファイル置き場
  data/interim/          # 中間ファイル(GeoJSON/parquet等、形式は実装に任せる)
```

### 6.1 道路網の取得とグラフ化

- 取得: osmnx で `network_type="walk"` を基本とし、対象範囲は §3
  - 取得方法は osmnx の Overpass 経由でよい。失敗時のリトライを入れる
- 歩行可能判定は osmnx の walk フィルタに任せるが、以下を明示的に**除外**:
  `highway in (motorway, motorway_link, trunk, trunk_link)`、`access=private`、`foot=no`
- グラフ簡略化: osmnx の simplify を適用(交差点間を1エッジに)
- **最大連結成分のみ残す**(孤立サブグラフ除去)
- `length_m`: 簡略化後エッジのジオメトリを EPSG:6677 に投影して線長を計算
- `is_bridge` / `is_tunnel`: OSMタグ `bridge` / `tunnel` が存在し `no` 以外なら1。
  simplify で複数wayが統合されたエッジは、**構成wayのいずれかが該当すれば1**(安全側)
- `geometry`: 簡略化後エッジの形状座標列(WGS84)をJSON化。小数6桁に丸める

### 6.2 水域距離 water_dist_m

江戸川区は荒川・中川・新中川・旧江戸川・江戸川に囲まれ、水路のタグ揺れも多いため、水域ジオメトリは以下の**和集合**で作る:

1. `waterway=*`(river, canal, stream, drain 等のライン)
2. `natural=water` のポリゴン
3. `landuse=basin`, `natural=coastline`
4. 上記を osmnx の features 取得(`ox.features_from_polygon` 等)でまとめて取る

手順:
- 全水域ジオメトリを EPSG:6677 に投影し、shapely `STRtree` に格納
- 各エッジの**中点**(投影座標)から最近傍水域までの距離を計算して `water_dist_m` に格納
- 300mを超える場合も実値を入れる(打ち切り上限 9999 でクリップ可)
- **NULLは許さない**。水域が1件も取れなかった場合はエラーで停止(江戸川区で水域ゼロはデータ取得失敗を意味する)

### 6.3 避難所 shelters

- 入力: 国土地理院「指定緊急避難場所データ」の江戸川区分。
  CSVを `data/raw/shelters_edogawa.csv` に置く前提とし、取得URLと手順をREADMEに書く
- 元データの災害種別フラグを `types` へマッピング。**語彙は以下に固定**(アプリ側と契約):
  - `flood`(洪水), `surge`(高潮), `earthquake`(地震), `tsunami`(津波), `fire`(大規模火災), `landslide`(崖崩れ等), `inland_flood`(内水氾濫)
  - 例: `"flood,surge,earthquake"`
- `elevation_m`: §6.4 と同じ方法で施設座標の標高を付与
- `coast_distance_m`: §6.2 と同じSTRtreeで施設座標から計算
- `nearest_node`: 全ノードのSTRtree(投影座標)で最近傍ノードを求める。
  最近傍距離が **200m超なら警告ログ**を出す(スナップ品質の異常検知)
- `capacity`: 元データに無ければ 0

### 6.4 標高 elevation_m

- 取得元: 国土地理院 標高タイル(`dem5a` テキスト形式、zoom 15)。
  URL形式: `https://cyberjapandata.gsi.go.jp/xyz/dem5a/{z}/{x}/{y}.txt`
- 手順: 対象bboxに必要なタイルを列挙 → ローカルにキャッシュDL(`data/interim/dem/`) →
  各エッジ中点・各避難所座標について該当タイルのセル値を引く
- `e`(欠測)セルは DEM10B テキストタイルでフォールバックする。
  タイルIDは `dem`、zoom 14、URL形式は
  `https://cyberjapandata.gsi.go.jp/xyz/dem/{z}/{x}/{y}.txt`。
  それでも欠測なら 0.0 を入れて警告ログ
- リクエストにはウェイト(0.1s以上)を入れ、キャッシュ済みタイルは再取得しない

### 6.5 SQLite出力

- 全insertは**単一トランザクション**で一括投入(性能とファイル整合性のため)
- 書き込み後 `VACUUM` と `ANALYZE` を実行
- 出力先: `preprocess/output/routing.db`

## 7. 受け入れ条件(実装AIが自己検証し、結果をREADMEに記録すること)

1. `nodes` 件数が 8,000〜80,000、`edges` 件数が 10,000〜120,000 のオーダー(江戸川区+バッファの歩行網として妥当な範囲)
2. グラフが単一連結成分であること(§6.1の処理後検証)
3. `water_dist_m` NULL件数 = 0。かつ `water_dist_m < 300` のエッジ比率が **15%以上**(河川・水路密集地帯なら満たすはず。満たさない場合は水域取得漏れを疑い停止)
4. `elevation_m` NULL件数 = 0。値域が -5.0〜+15.0 m に概ね収まる(江戸川区はゼロメートル地帯を含む低平地)
5. `is_bridge=1` のエッジが **50本以上**(江戸川区は大河川の橋梁と水路の小橋が多数。少なすぎたらタグ処理ミス)
6. `shelters` が10件以上、全件の `nearest_node` が実在ノードを指す(JOIN検証)
7. 検証探索: 西葛西駅(35.6647, 139.8586)と船堀駅(35.6837, 139.8646)それぞれの最近傍ノード間で、networkx の `shortest_path`(weight=length_m)が経路を返し、経路長が 1.5〜6.0 km に収まる
8. `routing.db` のファイルサイズが 80MB 以下(assets同梱の現実性。超える場合は geometry の座標丸めを5桁に落として再生成)。東京23区版ではGitHub通常Gitの100MB制限を避けるため95MB以下を上限とする
9. 検証は `05_write_db.py` 内の自動チェックとして実装し、1つでも失敗したら非0で終了する

## 8. スコープ外(実装するな・書くな)

- Flutter/Dart側の一切
- ハザードマップポリゴン(津波浸水想定・洪水浸水想定)の取り込み ※将来拡張
- 液状化予測図の取り込み ※将来拡張(READMEの将来課題に1行言及するのは可)
- リアルタイムデータ、日本全国対応、差分更新機構、GUI
