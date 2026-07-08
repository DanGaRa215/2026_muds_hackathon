# 仕様書③ Flutter UI統合: 自宅登録・ルート表示・候補切り替え

- 版: v1.0
- 対象: 実装AI(Claude Code)
- 前提: 仕様書①(routing.db)と仕様書②(lib/routing/)が完了済み
- **注意: §2 の公開APIは仕様書②の設計値。②の実装完了後、実際のシグネチャと差異があれば
  本仕様書ではなく②の実装を正とし、差異を作業ログに記録すること**

---

## 0. 作業上の絶対制約

1. 触ってよいのは `bosai_app/lib/` のみ。**`bosai_app/bosai_app/` は禁止**
2. `lib/routing/` 以下と `lib/db/database_helper.dart` は**読み出しのみ、変更禁止**
3. 状態管理はsetState直書きを踏襲。新パッケージ追加禁止
4. 既存の家具診断・EEW・履歴・状況チェックの動作を壊さない
5. 地図表示の実装は既存 `map_spike_screen.dart` の動作確認済みパターン
   (PMTilesのassetコピー → PmTilesVectorTileProvider)を流用する

## 1. 実装する機能(この3つだけ)

### 機能A: 自宅登録(prepare_screen.dart への追加)

- 「地図をタップして自宅を登録」導線を追加
- タップで自宅位置を選ぶ全画面地図(新規 `home_register_screen.dart`)を開く:
  - 地図は §0-5 のPMTilesパターンで表示。初期中心は江戸川区役所(35.7068, 139.8683)
  - タップ位置にマーカーを立て、「ここを自宅にする」ボタンで確定
  - 確定時に snap が null(グラフ範囲外、②の仕様)ならSnackBarで「対応エリア外です」と表示して確定させない
- 確定後、`PrecomputeService.precomputeAll` を呼ぶ:
  - onProgress をLinearProgressIndicatorに反映するモーダルを表示
  - 完了で「避難ルートを保存しました(オフラインで利用できます)」表示
  - 失敗時はエラー内容をダイアログ表示し、再試行ボタンを出す
- 自宅座標は既存 database_helper の自宅情報保存機能(偵察報告で存在確認済み)に保存。
  既存の保存形式を調べて合わせること(スキーマ変更禁止)
- **住所文字列ジオコーディング(geocoding パッケージ)はこの導線では使わない**(オフライン完結のため)。既存の address_geocoding_screen.dart は触らず残す

### 機能B: ルート表示(NaviScreen の置き換え)

- `shelter_card_screen.dart` 内のプレースホルダ `NaviScreen` を実装に置き換える(新規ファイル `lib/screens/navi_screen.dart` に切り出し、shelter_card_screen からは参照のみにする)
- 画面構成:
  - PMTiles地図(§0-5 パターン)
  - `PolylineLayer`: 選択中ルートの geometry を描画。線色 #1A73E8、太さ6、白縁取り(Polylineを白・太さ9で下に重ねる)
  - 現在地マーカー(geolocator、既存 map_spike_screen の取得実装を流用)
  - 目的地の避難所マーカーと名称ラベル
  - 初期カメラ: ルート全体が収まるbounds(flutter_map の CameraFit.bounds)
- ルートの取得優先順位:
  1. GPS取得成功 かつ 自宅から300m以上離れている → `RouteService.findRoute`(現在地からリアルタイム計算)
  2. それ以外(GPS不可・自宅近傍) → `PrecomputeService.loadPrecomputed` から該当ルートを表示
  - どちらを使ったかを画面上部に小さく表示(「現在地から計算」/「自宅からの保存ルート」)。デモで説明しやすくするため
- `usedFallback == true` のルートには警告バナーを表示:
  「この経路は通行危険箇所(アンダーパス等)を含む可能性があります」

### 機能C: 3候補切り替えと災害モード連動

- NaviScreen 上部に SegmentedButton で fastest / balanced / safest
  (表示名:「最短」「バランス」「安全重視」)。切り替えで線と数値を更新
- 各候補について表示: 徒歩時間(estMinutes、分単位切り上げ)、距離(km、小数1桁)、
  安全スコア(safetyScore、整数、"安全度 87/100" 形式)
- 災害モードは前画面フローから引き継ぐ:
  - status_check_screen の状況選択(偵察報告で存在確認済み)を調べ、
    その選択内容を `DisasterMode` にマッピングして shelter_card → navi に引数で渡す
  - マッピング規則: 水害系の状況(洪水・高潮・大雨)→ flood、それ以外 → earthquake。
    既存の状況語彙は実装時にコードを確認して対応表をコメントで残す
- **floodモード時のみ**、避難所リスト/NaviScreen に注意文言を常設表示:
  「大規模水害時は、時間に余裕がある場合は浸水しない地域への広域避難、
  余裕がない場合は近くの建物の3階以上への避難(垂直避難)が基本です。
  この経路は参考情報です」
  (江戸川区・江東5区の広域避難方針との整合。ルート表示より優先度の高い行政ガイダンスであることを示す)

## 2. 依存する公開API(仕様書②で定義)

```dart
enum DisasterMode { earthquake, flood }
enum WeightProfile { fastest, balanced, safest }

class RouteResult {
  final String shelterId;
  final DisasterMode mode;
  final WeightProfile profile;
  final double distanceM;
  final double penaltyM;
  final double estMinutes;
  final double safetyScore;
  final List<LatLng> geometry;
  final bool usedFallback;
}

class RouteService {
  static Future<RouteService> create();
  Future<RouteResult?> findRoute({required LatLng from, required String shelterId,
    required DisasterMode mode, required WeightProfile profile});
  Future<List<RouteResult>> findRoutesToAll({required LatLng from,
    required DisasterMode mode, required WeightProfile profile});
  List<ShelterInfo> sheltersFor(DisasterMode mode);
}

class PrecomputeService {
  Future<void> precomputeAll({required LatLng home,
    void Function(double progress)? onProgress});
  Future<List<RouteResult>> loadPrecomputed({required DisasterMode mode,
    required WeightProfile profile});
}
```

RouteService の初期化(create)は重い可能性があるため、アプリ起動時ではなく
**最初に必要になった画面で遅延初期化**し、シングルトンとして保持する
(`lib/routing_bootstrap.dart` 的な薄いホルダーを新設してよい)。

## 3. 変更ファイル一覧(これ以外を変更しない)

| ファイル | 変更内容 |
|---|---|
| `lib/screens/prepare_screen.dart` | 自宅登録導線の追加、precompute進捗UI |
| `lib/screens/home_register_screen.dart` | **新規**。地図タップ登録画面 |
| `lib/screens/navi_screen.dart` | **新規**。ルート表示画面(機能B/C) |
| `lib/screens/shelter_card_screen.dart` | プレースホルダNaviScreenの削除と新NaviScreenへの遷移差し替え、DisasterModeの引き渡し |
| `lib/screens/status_check_screen.dart` | 状況選択→DisasterModeマッピングの引き渡し(最小変更) |
| `lib/routing_bootstrap.dart` | **新規**(任意)。RouteService遅延初期化ホルダー |
| `pubspec.yaml` | 変更不要のはず。必要が生じたら理由を作業ログに書く |

map_spike_screen.dart は**変更せず残す**(開発用導線として有用)。PMTiles表示コードは
コピーではなく、可能なら共通Widget(`lib/widgets/offline_map.dart` 新規)に抽出して
navi_screen / home_register_screen の両方から使う。抽出が既存spike画面の変更を
伴う場合は、spike画面は触らずコード重複を許容する(既存を壊さない方を優先)。

## 4. 受け入れ条件

1. `flutter analyze` エラー0
2. **機内モードで通しデモが成立する**: アプリ起動 → 状況選択 → 避難所カード →
   地図に青いルート線・現在地・避難所マーカー表示(事前に自宅登録・事前計算済みの状態から)
3. 3プロファイル切り替えで線・徒歩時間・距離・安全スコアが変化する
4. floodモードで注意文言が表示され、earthquakeでは表示されない
5. 自宅未登録状態で避難所カード→ナビに進んでもクラッシュせず、
   「自宅を登録してください」導線(prepare_screenへの誘導)が出る
6. GPS拒否/取得失敗時も、保存ルート表示にフォールバックして動作する
7. 既存機能(家具診断・EEW・履歴)が引き続き動作する

## 5. デモ手順書(実装完了時に DEMO.md として作成すること)

1. Wi-Fi/モバイル通信ONの状態で自宅登録(西葛西付近を推奨)→ 事前計算完了を確認
2. 機内モードON
3. アプリ再起動 → EEW/状況選択 → 避難所カード → ルート表示
4. プロファイル切り替え、モード差し替え(地震⇔水害)の見せ方
5. 各画面のスクリーンショット取得ポイント

## 6. スコープ外(実装するな)

- ターンバイターン案内(音声・矢印)
- ルート逸脱の自動検知・自動リルート(手動の「再計算」ボタンは可、ただし余裕があれば程度)
- 避難所データ・地図データのオンライン更新
- 広域避難(区外)ルートの計算 ※注意文言での案内に留める
- 多言語対応、アクセシビリティ対応の作り込み
