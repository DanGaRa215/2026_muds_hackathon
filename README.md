# BosaiApp - 総合防災アプリ MVP

完全オフライン動作する防災アプリのMVP基盤です。

## 機能

1. **AI家具安全診断** - 写真+補助入力から家具の転倒危険度を3段階評価（MVPはルールベース）
2. **オフライン避難誘導** - EEWデモ→身を守る→状況確認→避難所推薦→簡易ナビ
3. **避難準備** - 自宅情報の事前登録
4. **診断履歴** - 過去の診断結果をSQLiteに保存・閲覧

## Xcodeへの組み込み手順

### 1. Xcodeプロジェクト作成

1. Xcode → File → New → Project → iOS → App
2. Product Name: `BosaiApp`
3. Interface: SwiftUI / Language: Swift
4. プロジェクトの保存先: このリポジトリの `BosaiApp/` ディレクトリ
5. 自動生成された `ContentView.swift` は削除する（`HomeView.swift` がエントリポイント）
6. 自動生成された `BosaiAppApp.swift` は本リポジトリのものに置き換える

### 2. ソースファイル追加

`BosaiApp/BosaiApp/` 以下の全 `.swift` ファイルをXcodeプロジェクトに追加:

- File → Add Files to "BosaiApp" で以下のフォルダごと追加:
  - `Models/`
  - `Database/`
  - `Services/`
  - `ViewModels/`
  - `Views/`
  - `Protocols/`
  - `BosaiAppApp.swift`

### 3. GRDB.swift の追加（SPM）

1. Xcode → File → Add Package Dependencies
2. URL: `https://github.com/groue/GRDB.swift`
3. Version: Up to Next Major `7.0.0`
4. Target: `BosaiApp` を選択して追加

### 4. Info.plist 設定

`BosaiApp/BosaiApp/Info.plist` をプロジェクトに含める。以下のキーが設定済み:

- `NSPhotoLibraryUsageDescription` - 写真ライブラリアクセス（家具診断用）

通知権限はコードから動的にリクエストするため Info.plist への追記は不要です。

### 5. ビルド設定

- Deployment Target: iOS 17.0 以上
- Swift Language Version: 5.9 以上

### 6. 初回起動時の確認

1. ビルド＆実行
2. 通知権限のダイアログが表示される → 許可
3. SQLiteにシードデータ（葛飾区周辺の避難所10件）が自動投入される

### 動作確認

- **機内モード**で全フローが動作することを確認
- 「避難準備」で自宅情報を入力後、「EEWデモ起動」を実行
- 「津波警報」チェックON/OFFで候補の並び順が変わることを確認

## ファイル構成

```
BosaiApp/BosaiApp/
├── BosaiAppApp.swift              # アプリエントリポイント
├── Info.plist                     # 権限設定
├── Models/
│   ├── Shelter.swift              # 避難所モデル（GRDB）
│   ├── DiagnosisHistory.swift     # 診断履歴モデル（GRDB）
│   ├── HomeInfo.swift             # 自宅情報モデル（GRDB）
│   └── DiagnosisInput.swift       # 診断入力/結果/座標/経路の型定義
├── Protocols/
│   ├── DiagnosisEngine.swift      # 診断エンジンプロトコル
│   ├── RouteProvider.swift        # 経路探索プロトコル
│   └── MapProvider.swift          # 地図表示プロトコル
├── Database/
│   └── AppDatabase.swift          # DB初期化・マイグレーション・CRUD
├── Services/
│   ├── MockDiagnosisEngine.swift  # ルールベース診断（モック）
│   ├── StraightLineRouteProvider.swift # 直線距離+方位角（モック）
│   ├── EmptyMapProvider.swift     # 空の地図プロバイダ（モック）
│   ├── ShelterScorer.swift        # 避難所スコアリング
│   └── NotificationService.swift  # ローカル通知管理
├── ViewModels/
│   ├── DiagnosisViewModel.swift   # 家具診断VM
│   ├── HistoryViewModel.swift     # 診断履歴VM
│   ├── EvacuationViewModel.swift  # 避難フローVM
│   └── HomeInfoViewModel.swift    # 自宅情報VM
└── Views/
    ├── Home/
    │   └── HomeView.swift         # ホーム画面（4ボタン）
    ├── Diagnosis/
    │   ├── DiagnosisInputView.swift   # 診断入力フォーム
    │   ├── DiagnosisResultView.swift  # 診断結果（参考値ラベル付き）
    │   └── HistoryView.swift          # 診断履歴一覧
    ├── Evacuation/
    │   ├── EvacuationFlowView.swift   # 避難フロー全体コンテナ
    │   ├── SituationCheckView.swift   # 状況確認（チェック4項目）
    │   ├── ShelterCardView.swift      # 候補カード（YES/NO）
    │   ├── NavigationGuideView.swift  # 簡易ナビ（方位+距離）
    │   └── NoMoreSheltersView.swift   # 全候補拒否時
    └── Settings/
        └── SettingsView.swift     # 避難準備（自宅情報入力）
```

## モック → 本実装への差し替えガイド

### メンバーA: Core ML 診断エンジン

**対象ファイル**: `Services/MockDiagnosisEngine.swift`

1. `CoreMLDiagnosisEngine` クラスを新規作成し `DiagnosisEngine` プロトコルに準拠
2. YOLOv8 の Core ML モデル (`.mlmodelc`) をプロジェクトに追加
3. `diagnose(image:input:)` メソッドで:
   - `image` を `CVPixelBuffer` に変換
   - Core ML モデルで推論実行
   - 検出結果と `input` パラメータを組み合わせて `DiagnosisResult` を返す
4. `DiagnosisViewModel.swift` の `engine` プロパティを `CoreMLDiagnosisEngine()` に変更

```swift
// 差し替え箇所（DiagnosisViewModel.swift）
private let engine: DiagnosisEngine = CoreMLDiagnosisEngine() // ← 変更
```

### メンバーB: A* 経路探索

**対象ファイル**: `Services/StraightLineRouteProvider.swift`

1. `AStarRouteProvider` クラスを新規作成し `RouteProvider` プロトコルに準拠
2. オフライン道路ネットワークデータをバンドルに含める
3. A* アルゴリズムで `route(from:to:)` を実装
4. `ShelterScorer.swift` と `EvacuationViewModel.swift` の `routeProvider` を差し替え

```swift
// 差し替え箇所（EvacuationViewModel.swift）
private let routeProvider: RouteProvider = AStarRouteProvider() // ← 変更
```

### メンバーC: MapLibre + PMTiles 地図表示

**対象ファイル**: `Services/EmptyMapProvider.swift`

1. MapLibre Native iOS SDK を SPM で追加
2. PMTiles ファイルをバンドルに含める
3. `MapLibreMapProvider` クラスを新規作成し `MapProvider` プロトコルに準拠
4. `mapView(route:)` で MapLibre の `UIViewRepresentable` ラッパーを返す
5. `NavigationGuideView.swift` の `mapProvider` を差し替え、`frame(height: 0)` を適切なサイズに変更

```swift
// 差し替え箇所（NavigationGuideView.swift）
private let mapProvider = MapLibreMapProvider() // ← 変更
// .frame(height: 0) → .frame(height: 300) 等に変更
```

## 外部依存

| ライブラリ | バージョン | 用途 |
|-----------|-----------|------|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 7.x | SQLiteデータベース |
