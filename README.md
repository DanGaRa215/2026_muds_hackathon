# 総合防災アプリ MVP（Flutter版・動く骨格）

設計書v2に対応した最低限デモ。**UIは最低限、後から本実装に差し替えられる設計**を優先。

## セットアップ手順

前提：Flutter SDK導入済み（`flutter doctor` で確認）／iOS実行にはXcode（シミュレーター用）

```bash
# 1. プロジェクト生成
flutter create bosai_app

# 2. 生成された bosai_app/ の pubspec.yaml と lib/ を本一式で置き換え

# 3. 依存取得
cd bosai_app
flutter pub get

# 4. iOSシミュレーター起動 → 実行
open -a Simulator
flutter run
```

Android実行の場合はAndroid Studio（SDK・エミュレーター）が必要。

**iOSで写真選択（カメラ）まで使う場合**は `ios/Runner/Info.plist` に追加：

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>家具診断のため写真を選択します</string>
<key>NSCameraUsageDescription</key>
<string>家具診断のため撮影します</string>
```

## このMVPで動くもの

- ホーム4ボタン（家具診断 / 避難準備 / 診断履歴 / EEWデモ）
- **EEWデモフロー**：身を守る全画面（10秒カウントダウン）→ 状況確認（チェック×4）→ 避難所カードYES/NOループ（最大5件）→ 全NOで「高台へ」最終指示 → 簡易ナビ → 到着・安否メモ
- **家具診断**：写真選択 + 震度/固定状況入力 → モック判定（3段階+「※参考値」表示）→ SQLite履歴保存
- **避難準備**：自宅情報（構造・階数）のSQLite保存、避難所リスト表示
- ダミー避難所5件をSQLite（sqflite）にシード済み

## オフライン地図データ（PMTiles）

`assets/demo_area.pmtiles` にオフライン地図データを同梱しています。

| 項目 | 内容 |
|---|---|
| 対象地域 | 江戸川区周辺 |
| 含まれるデータ | 道路（OSM highway タグ） |
| ズームレベル | z10 〜 z16 |
| ファイルサイズ | 約 2.7MB |
| データソース | OpenStreetMap（Geofabrik 関東抽出） |

### 地図データの再生成手順

対象地域やズームレベルを変更したい場合は、以下の手順で再生成できます。

```bash
# 必要ツール（未インストールの場合）
brew install osmium-tool tippecanoe pmtiles

# 1. 関東OSMデータの取得（約450MB・初回のみ）
curl -L -o kanto-latest.osm.pbf \
  https://download.geofabrik.de/asia/japan/kanto-latest.osm.pbf

# 2. 対象地域の切り出し（bbox: 西,南,東,北）
osmium extract \
  --bbox 139.84,35.64,139.92,35.72 \
  kanto-latest.osm.pbf \
  -o demo_area.osm.pbf

# 3. 道路データの抽出・GeoJSON変換
osmium tags-filter demo_area.osm.pbf w/highway -o roads.osm.pbf
osmium export roads.osm.pbf -o roads.geojson

# 4. PMTiles生成
tippecanoe \
  -o demo_area.pmtiles \
  --minimum-zoom=10 \
  --maximum-zoom=16 \
  --drop-densest-as-needed \
  roads.geojson

# 5. 検証（zoom・bboxが正しいか確認）
pmtiles show demo_area.pmtiles
```

生成した `demo_area.pmtiles` を `bosai_app/assets/` に配置すれば差し替え完了です。

> **注意**: ファイルサイズが大きくなりすぎる場合は、bboxを狭めるか `--maximum-zoom=15` に下げてください。

## 差し替えポイント（担当別）

| ファイル | 現状 | 差し替え先 | 担当 |
|---|---|---|---|
| `lib/logic/diagnosis_engine.dart` | ルールベースのモック | YOLOv8→TFLite推論（tflite_flutter） | A |
| `lib/logic/shelter_recommender.dart` | 距離+簡易重みのダミースコア | スコア関数・16パターン検証版 | B |
| `lib/screens/shelter_card_screen.dart` の `NaviScreen` | 地図プレースホルダ | flutter_map(or maplibre_gl)+PMTiles+A* | B/C |
| EEW起動（現状ホームのボタン） | 直接起動 | 気象庁API WebSocket受信→flutter_local_notifications→**通知タップで起動** | C |
| `lib/db/database_helper.dart` の `_seedShelters` | ダミー5件 | 国土数値情報ベースの実DB | D |
