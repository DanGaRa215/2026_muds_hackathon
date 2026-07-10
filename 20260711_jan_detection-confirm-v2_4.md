# 20260711_jan_detection-confirm-v2_4 — Flutter 作業記録

ブランチ: `20260711_jan_detection-confirm-v2_4`  
前提: v2.3（代表1件表示・出典・文言平易化）マージ済み

---

## 目的

FastAPI v2.4 の2段階 API に合わせ、**検出確認画面**を挟んでからリスク結果を表示する。

```
旧: 診断する → いきなり結果カード
新: 診断する → /detect → 確認・編集 → /diagnose(JSON) → 結果カード（v2.3: 1件）
```

---

## 実施内容

### 1. `DiagnosisApiClient` 2段階化

| メソッド | エンドポイント | タイムアウト |
|---|---|---|
| `detect()` | `POST /detect` | 30秒 [DESIGN v2.4] |
| `diagnoseFromDetection()` | `POST /diagnose`（detection JSON） | 15秒 [DESIGN] |
| `diagnose()`（既存） | `POST /diagnose`（画像） | 120秒（後方互換） |

### 2. 状態機械（`furniture_diagnosis_ui_screen.dart`）

| Phase | 表示 |
|---|---|
| `detecting` | 「写真を解析しています…」 |
| `confirmDetection` | 検出確認カード |
| `diagnosing` | 「リスクを計算しています…」 |
| `result` | v2.3 の1件結果カード |

保持 State:

- `_detection` — `/detect` 生結果（不変）
- `_editedDetection` — 編集コピー（`/diagnose` 送信元）
- `_selectedFurnitureIndex` — 複数検出時のラジオ選択

### 3. 検出確認 UI

| ファイル | 役割 |
|---|---|
| `lib/utils/detection_editor.dart` | deepCopy / 固定具 ON・OFF / submission 1件化 |
| `lib/widgets/detection_confirm_card.dart` | 確認画面（アイコン・絵文字なし） |

**編集可能**: 家具 class / wardrobe profile / 固定具有無  
**編集不可**: install_quality / confidence / bbox

- 固定具 ON（新規）→ `unverified`, `confidence: 1.0`
- Vision が `correct` で検出したものは維持
- 複数家具 → ラジオで1件選択 → submission は1件のみ

注記: 「写真で確認できなかった固定具は、安全のためリスクの軽減に反映していません。」

### 4. デモモード

- `_buildDetectionPayload()` — 食器棚+L字 + 本棚の2件検出
- **確認画面を必ず通過**（スキップ分岐なし）
- 確定後は `_buildOkPayload()` 固定JSON（編集は結果に未反映・コメント明記）

---

## コミット構成

| コミット | 概要 |
|---|---|
| `8905b6d` | `DiagnosisApiClient` detect / diagnoseFromDetection |
| `98f125e` | `DetectionEditor` + `DetectionConfirmCard` |
| `d9f27bf` | 画面フロー2段階化 |
| `210e5ff` | `detection_confirm_test.dart` |

---

## テスト

- **flutter test 51件通過**（1 skip は既存 sqflite 環境制約）
- 新規9件: 固定具編集、submission 1件、deepCopy 不変、確認画面 widget

---

## セルフレビュー

- [x] 確認画面をスキップする経路なし（デモ含む）
- [x] `_detection` を直接 mutate していない
- [x] 複数検出時ラジオ → 選択1件のみ `/diagnose` 送信
- [x] ユーザー ON 固定具 → `unverified`
- [x] Vision `correct` 維持
- [x] 確認画面にアイコン・絵文字なし（v2.3 Part D 継承）
- [x] 未確認固定具の注記あり

---

## FastAPI 側（別リポジトリ）

`POST /detect` / `validate_schema` は
`2026_muds_hackthaon_FastAPI` の同ブランチで実施。
