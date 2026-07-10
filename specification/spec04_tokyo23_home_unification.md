# 仕様書④ 東京23区対応・自宅位置情報の単一情報源化

- 版: v1.1
- 対象: 実装AI(Claude Code / Codex)。本書のみで実装方針と停止条件を判断できること
- 成果物: 東京23区デモ成立のための実装変更、東京23区版 `routing.db`、関連ドキュメント更新
- 前提: 仕様書①〜③の `routing.db` / `lib/routing` / Flutter UI 統合が存在する

---

## 0. 作業上の絶対制約

1. `main` / `develop` / detached HEAD / ブランチなしで実装しない。PR target は原則 `develop` とし、差分確認はまず `origin/develop...HEAD` を使う
2. 本PRの主目的は「東京23区全域で、自宅登録から避難所提案・道路経路ナビまで成立させること」とする
3. `routing.db` の東京23区再生成、`routing.db` 内 shelters の23区対応、`nearest_node` 再計算、asset差し替えを本PRに含める
4. A*、Dijkstra、snap、コスト関数など経路探索の数値ロジックは変更しない
5. 家具診断、EEW、履歴、状況チェックの挙動は変更しない
6. 本PRの目的に関係しないリファクタ、整形、import順変更、UI改善、a11y改善を入れない
7. 自宅座標の唯一の情報源は `home_info.lat` / `home_info.lon` とする。`structure` 文字列へ座標を埋め込む規約を新規に増やさない

## 1. 背景

ハッカソン審査用デモでは「自宅住所登録 → オフラインマップ → EEWシミュレーション → 避難所提案 → 避難ナビ」の一連の流れを、東京23区内で成立させる必要がある。

当初は既存 `routing.db` が江戸川区+1.5kmのみだったため、23区内の範囲外地点では直線距離案内へ縮退する計画だった。追加方針により、東京23区全域のOSM歩行者道路グラフと23区避難所を含む `routing.db` を再生成し、世田谷区など江戸川区以外でも道路経路線を表示できる状態に変更する。

## 2. 現状課題

### 2.1 自宅位置の二重規約

住所登録画面は `home_info.lat` / `home_info.lon` に自宅座標を保存する。一方、EEW後の `NaviScreen` は `structure` 内の `||home=lat,lon` だけを読む経路があり、住所登録済みでも未登録扱いになる可能性があった。

### 2.2 相互クロバー

構造/階数保存と住所/地図登録が同じ全列 `REPLACE` API を使っており、準備画面と住所登録画面が互いのデータを既定値で上書きする可能性があった。

### 2.3 デモDB分裂

通常画面は `bosai_app.db` の `DatabaseHelper` を使うが、一部デモ画面は `demo_database_helper.db` の `DemoDatabaseHelper` を参照していた。このため通常の住所登録とデモマップの表示対象が分裂していた。

### 2.4 routing.db の旧制約

旧 `routing.db` は江戸川区+1.5kmのみ、55,146 nodes / 83,629 edges / shelters 112件だった。東京23区全域で経路線を出すには、OSM道路グラフ生成、23区避難所抽出、`nearest_node` 再計算、asset差し替えが必要である。

## 3. 目標

1. 自宅座標は `home_info.lat` / `home_info.lon` だけを正として読み書きする
2. `home_registered=1` のときだけ登録済みと判定し、単に行があるだけでは登録済みにしない
3. 家具診断・準備画面の構造/階数保存と、住所/地図登録の lat/lon/address 保存が相互に破壊されない
4. レガシーの `structure ||home=lat,lon` は自動移行され、実装後の `||home=` リテラルは移行コード1箇所だけに残る
5. `DemoMapScreen` と `DemoAddressGeocodingScreen` は通常DBを参照し、`DemoDatabaseHelper` 参照は0件になる
6. 東京23区内の住所登録と地図タップ登録は保存でき、23区外は保存前に拒否される
7. 東京23区版 `routing.db` を生成し、`bosai_app/assets/routing.db` へ差し替える
8. `routing.db` の shelters は23区避難所を含み、全件の `nearest_node` が実在ノードを指す
9. 西葛西周辺だけでなく、三軒茶屋〜新宿など23区西側を含む実データ経路探索が成立する
10. ナビ画面は未登録、登録済み+ルートあり、登録済み+ルートなしの3状態で破綻しない

## 4. 非目標

- 23区外対応
- ハザードマップポリゴン、液状化予測図、津波・洪水浸水想定の取り込み
- スコアリング、A*、Dijkstra、snap、コスト関数など経路探索数値ロジックの変更
- 家具診断、EEW、履歴、状況チェックの挙動変更
- 無関係なリファクタ、整形、UI改善、a11y改善
- `main` への直接コミット

## 5. 対象範囲と実測値

| データ | 実測値 | 23区対応 |
|---|---:|---|
| `bosai_app/assets/tokyo23_buffered.pmtiles` | 68MB、東京都全域 zoom 10-16 | 対応可 |
| `bosai_app/assets/shelters.db` | 2,179件、23区全区 | 対応可 |
| `bosai_app/assets/routing.db` | 108.6MB、479,627 nodes、703,264 edges | 対応済み |
| routing.db meta bbox | lat 35.468135-35.831014 / lon 139.546313-139.935467 | 23区+1.5kmバッファ |
| routing.db shelters | 2,179件、nearest_node不整合0件 | 対応済み |

`isInRoutingArea` は最近傍ノード300mスナップに依存する。東京23区版 `routing.db` 生成後も、水面・巨大敷地・道路から離れた地点などで300m以内に道路ノードが無い場合は範囲外として扱う。

## 6. DB設計方針(単一情報源化)

`home_info.lat` / `home_info.lon` を唯一の座標情報源とする。ただし既存の `lat` / `lon` は `NOT NULL` かつ既定値を持つため、登録済み判定用に以下の列を追加する。

```sql
home_registered INTEGER NOT NULL DEFAULT 0
```

用途別の部分更新APIを使う。

```dart
Future<void> saveHomeLocation({
  required double lat,
  required double lon,
  String? address,
  String? pmtilesPath,
});

Future<void> saveHomeProfile({
  required String structure,
  required int floor,
});

Future<Map<String, dynamic>?> getRegisteredHome();

Future<void> clearPrecomputedRoutes();
```

- `saveHomeLocation`: 位置系列だけを更新し、`home_registered=1` にする。自宅変更時は `clearPrecomputedRoutes()` を呼ぶ
- `saveHomeProfile`: 構造/階数だけを更新し、住所・座標・PMTilesパスを保持する
- `getRegisteredHome`: `home_registered=1` の行だけを返し、それ以外は `null`
- `clearPrecomputedRoutes`: 自宅変更時に旧ルートを全削除する

## 7. レガシーデータ移行方針

`DatabaseHelper._repairHomeInfo()` を `onOpen` と `onUpgrade` 末尾で冪等実行する。

1. `structure` に `||home=` を含む場合
   - `lat,lon` をパースできれば `home_info.lat` / `home_info.lon` に反映し、`home_registered=1` にする
   - `structure` から `||home=...` サフィックスを除去する
   - パース失敗時もサフィックス除去だけは行う
2. `home_registered=0` かつ `(address != '未登録住所' または lat/lon が既定値以外)` の場合
   - 旧住所フロー保存の救済として `home_registered=1` にする

`'||home='` リテラルはこの移行コード1箇所だけに残す。

## 8. デモモード統一方針

- `DemoMapScreen`: `DatabaseHelper.getRegisteredHome()` を読む。`pmtiles_path` が空なら同梱 `tokyo23_buffered.pmtiles` を使う
- `DemoAddressGeocodingScreen`: 保存先を `DatabaseHelper.saveHomeLocation` に変更する
- デモダッシュボードの「自宅の住所登録」は通常画面を開き、通常DBに統一する
- `DemoDatabaseHelper` は呼び出し箇所ゼロになった時点で削除する

## 9. 東京23区対応方針

### 9.1 23区判定

23区近似 bbox を以下で定義する。

```text
lat 35.50-35.83
lon 139.55-139.93
```

住所フローでは bbox 判定に加え、23区名一致との AND 条件で保存可否を決める。境界近傍の浦安・川崎縁辺などを誤受入れする可能性はデモ用途の制約として扱う。

### 9.2 住所フロー

- 区名マッチと bbox 判定で23区外を保存前に拒否する
- 保存は `DatabaseHelper.saveHomeLocation` を使う
- 登録後、`routing.db` 圏内なら precompute を実行し、圏外なら正常系としてスキップして通知する
- `demo_address_geocoding_screen.dart` も同じ判定と保存先に揃える

### 9.3 地図タップフロー

- 23区 bbox 外は拒否する
- 23区 bbox 内は保存可とする
- `routing.db` 圏内なら precompute を実行する
- 300mスナップに失敗した地点では `precomputeAll` を呼ばず、`StateError('自宅座標がルーティング範囲外です')` を正常系で発生させない

### 9.4 routing.db 生成

- `preprocess/01_fetch_osm.py`: Nominatimで東京23区各区の行政界を取得し、union + 1.5kmバッファでOSM道路網と水域を取得する
- `preprocess/04_build_shelters.py`: `bosai_app/assets/shelters.db` から `city_code IN 13101..13123` を抽出する
- `nearest_node`: 東京23区版ノードSTRtreeで全避難所分を再計算する
- `05_write_db.py`: 23区サイズの受け入れ条件、23区東西2系統の経路検証、200MB以下のサイズ検証を行う
- 生成後の `preprocess/output/routing.db` を `bosai_app/assets/routing.db` へ差し替える
- `RoutingDatabase._assetRevision` を更新し、既存端末ローカルコピーを再展開させる

### 9.5 避難所提案とナビ

`routing.db` 圏内では全23区避難所を母集団にし、自宅からの直線距離で上位候補を粗選抜したうえで、道路経路距離を計算できた候補を経路距離順に最大5件表示する。災害種別は候補除外条件ではなくラベルとして扱い、現在モード未指定・未整備の場合はカードとナビで注意表示する。`routing.db` スナップに失敗した場合は、`ShelterDatabase.queryNearest(preferDisasterType: false)` により `shelters.db` から直線距離順5件を返し、ナビ画面は縮退表示する。

モードと列の対応は以下に固定する。

| モード | 対象列 |
|---|---|
| `earthquake` | `t_earthquake` または `t_fire` |
| `flood` | `t_flood` または `t_storm_surge` |

`GsiShelter` から `ShelterInfo` へ渡す場合は adapter を設け、`nearestNode=-1` をセンチネルにする。`capacity` / `elevation_m` が `null` の場合、UI表示は「不明」とする。

### 9.6 NaviScreen状態機械

| 状態 | 表示 |
|---|---|
| 未登録 | 従来どおり「自宅登録へ」 |
| 登録済み + ルートあり | 従来の地図 + 経路線 + 候補切り替え |
| 登録済み + ルートなし | 縮退ビュー。地図、自宅マーカー、避難所マーカー、直線距離、8方位、「経路データ未整備」バナーを表示 |

ルート解決には第3フォールバックとして「自宅起点 `findRoute`」を追加する。住所フローで precompute が未実行でも、`routing.db` 圏内なら経路線が出るようにする。

## 10. 実装対象ファイル候補

| ファイル | 変更内容 |
|---|---|
| `bosai_app/lib/db/database_helper.dart` | `home_registered` カラム追加、移行、部分更新API |
| `bosai_app/lib/services/home_area_service.dart` | 23区bbox判定、precomputeラッパ、GSI adapter、フォールバック検索 |
| `bosai_app/lib/db/shelter_database.dart` | `queryNearest` 追加。SELECT のみ |
| `bosai_app/lib/screens/navi_screen.dart` | `home_info` カラム読み、縮退ビュー、第3ルートフォールバック |
| `bosai_app/lib/screens/prepare_screen.dart` | `||home=` 保存廃止、`saveHomeProfile` 化 |
| `bosai_app/lib/screens/home_register_screen.dart` | 23区bbox判定へ変更 |
| `bosai_app/lib/screens/address_geocoding_screen.dart` | 区名判定、`saveHomeLocation`、登録後precompute |
| `bosai_app/lib/screens/demo_address_geocoding_screen.dart` | 通常DB化、住所フローと同じ保存処理 |
| `bosai_app/lib/screens/demo_map_screen.dart` | 通常DB読み |
| `bosai_app/lib/screens/home_screen.dart` | 東京23区デモ文言へ変更 |
| `bosai_app/lib/screens/shelter_card_screen.dart` | フォールバック分岐、距離表示、不明表示 |
| `bosai_app/lib/db/demo_database_helper.dart` | 削除 |
| `bosai_app/lib/screens/map_spike_screen.dart` | `getRegisteredHome` 化の小変更 |
| `bosai_app/lib/routing/routing_db.dart` | asset revision更新 |
| `preprocess/*.py` | 東京23区版 `routing.db` 生成・検証 |
| `bosai_app/assets/routing.db` | 東京23区版へ差し替え |
| `README.md` / `DEMO.md` / `preprocess/README.md` | 23区実データへ更新 |

## 11. 受け入れテスト

### 11.1 自動確認

1. `flutter analyze --no-fatal-infos --no-fatal-warnings` がエラー0
2. `flutter test` が通る
3. `git diff --check` が通る
4. `git grep -F "||home="` が `database_helper.dart` の移行コード1箇所だけを返す
5. `git grep -n "DemoDatabaseHelper"` が0件
6. `preprocess/.venv/bin/python run_all.py --force --geom-decimals 5` が全項目PASSする
7. `routing.db` 検証結果が以下を満たす
   - nodes=479,627 / edges=703,264
   - shelters=2,179 / nearest_node不整合=0
   - 西葛西〜船堀 2,507m
   - 三軒茶屋〜新宿 6,966m
   - DBサイズ 108.6MB

### 11.2 手動シナリオ

| シナリオ | 内容 | 期待結果 |
|---|---|---|
| A 江戸川回帰 | 西葛西付近で登録、EEW、避難所、ナビへ進む | 従来どおり経路線が出る |
| B 23区西側 | 世田谷区または三軒茶屋付近で登録、EEW、避難所、ナビへ進む | 道路経路線が出る。「自宅登録へ」は出ない |
| C 23区外拒否 | 市川市など23区外住所を入力する | 「対象外です」で保存されない |
| D レガシー移行 | `structure` に `||home=lat,lon` を持つ行で起動する | 自動移行され、以後 `structure` に座標を持たない |
| E 相互非破壊 | 家具/準備画面保存と住所登録を交互に行う | 構造/階数と住所/座標が互いに保持される |
| F 未登録 | `home_registered=0` または行なしでナビへ進む | 従来どおり自宅登録導線が出る |
| G スナップ不可 | 水面や道路から300m超離れた地点を選ぶ | 事前計算はスキップされ、縮退ナビが表示される |

## 12. リスクと停止条件

### 12.1 リスク

- `routing.db` が108.6MBに増えるため、アプリ初回展開とグラフロード時間が増える
- 23区避難所2,179件のうち、routing語彙の `types` が空の行が1,220件ある。既存ロジックではルート候補から除外される
- 23区 bbox は近似であり、境界近傍で誤受入れが起こり得る。デモ用途の制約として許容する
- 300mスナップに失敗する地点では、23区内でも経路線を出せない。縮退ビューで安全に処理する
- 修正前にクロバー済みで座標が失われた中間状態DBは復元不能。未登録扱いとし、再登録を促す

### 12.2 停止条件

実装中に以下が判明した場合は作業を停止し、差分と判断材料を報告する。

- `routing.db` の東京23区生成がOverpass・メモリ・サイズ制約で完走できない
- `routing.db` が200MBを超え、`--geom-decimals 5` でも収まらない
- `home_info` スキーマや既存保存フローが本仕様と異なる
- `DemoDatabaseHelper` に `home_info` 以外の生きた用途が見つかる
- 本PRの主目的を超えるレビュー指摘や追加依頼が入る

---

## 付録: 実測検証

- `preprocess/.venv/bin/python run_all.py --force --geom-decimals 5`
- 検証日時: 2026-07-10T01:39:16.466656+00:00
- 総合判定: 全て合格
- `routing.db`: 108.6MB / 479,627 nodes / 703,264 edges / shelters 2,179
- 経路検証: 西葛西〜船堀 2,507m、三軒茶屋〜新宿 6,966m
