# 仕様書② Dartルーティングロジック層: lib/routing/

- 版: v1.0
- 対象: 実装AI(Claude Code)。作業リポジトリの `bosai_app/` 配下のみを対象とする
- 前提: 仕様書①の成果物 `routing.db` が `bosai_app/assets/routing.db` に配置済み
- 本層は**UIを一切含まない純ロジック**。画面・Widget・地図描画は仕様書③の範囲

---

## 0. 作業上の絶対制約

1. 触ってよいのは `bosai_app/lib/` と `bosai_app/test/`、`bosai_app/pubspec.yaml`(assets追記のみ)
2. **`bosai_app/bosai_app/`(入れ子テンプレート)には一切触るな**
3. `lib/db/database_helper.dart` への変更は §7 のマイグレーション1点のみ許可
4. 既存画面・既存機能(家具診断、EEW、履歴、避難所カード)のコードを変更しない
5. 状態管理パッケージ(Riverpod/Provider/Bloc)の導入禁止
6. 新規依存の追加は不可。既存の sqflite / path / path_provider / latlong2 / geolocator で完結させる

## 1. 設計の背景(実装判断の根拠として読むこと)

技術調査(Deep Research)の結論を反映した確定設計:

- 自前A* + SQLiteはこの規模(江戸川区、数万ノード)で妥当。既存エンジン(GraphHopper等)は不採用
- **災害モードは `earthquake` と `flood`(洪水・高潮)の2つ**。江戸川区は江東5区広域避難計画の対象で、区のハザードマップも洪水・高潮を最重点に置いており(区の大半が浸水想定域)、独立した津波モードは実装しない(高潮・洪水と同系の水害としてfloodに包含する)
- **floodモードではアンダーパス・トンネルをハード制約(通行不可)にする**。江東5区・江戸川区の公式資料がアンダーパス・地下施設を浸水時の危険箇所と明示しているため、ソフトペナルティで「通れる扱い」にしてはならない
- 橋はソフトペナルティに留める。江戸川区は河川に囲まれ、橋が広域避難の必須経路であり、一律に強く避けると避難自体が成立しない
- 加法型ペナルティは「最適避難モデル」ではなく**説明可能な近似モデル**として実装する

## 2. ファイル構成(確定)

```
lib/routing/
  models.dart            # RouteResult, RouteRequest, 列挙型
  graph.dart             # インメモリグラフ(フラット配列 + 隣接リスト)
  routing_db.dart        # routing.db のassetコピーと読み込み
  cost_function.dart     # 重みテーブルとEdgeCost計算、エッジフィルタ
  astar.dart             # A*探索(h=0でDijkstra化)
  snap.dart              # 座標→最近傍ノード
  route_service.dart     # 公開API(探索の窓口、isolate制御)
  precompute_service.dart# 事前計算と precomputed_routes 永続化
test/routing/
  astar_test.dart
  cost_function_test.dart
  precompute_test.dart
```

## 3. 公開API(確定。仕様書③がこの型に依存する)

```dart
// models.dart
enum DisasterMode { earthquake, flood }
enum WeightProfile { fastest, balanced, safest }

class RouteResult {
  final String shelterId;
  final DisasterMode mode;
  final WeightProfile profile;
  final double distanceM;        // 実距離合計(ペナルティ含まず)
  final double penaltyM;         // ペナルティ合計(m換算)
  final double estMinutes;       // distanceM / 66.7 (徒歩4km/h)
  final double safetyScore;      // 100 * distanceM / (distanceM + penaltyM)。100が最安全
  final List<LatLng> geometry;   // 描画用座標列(latlong2)
  final bool usedFallback;       // ハード制約を緩めて算出した場合 true(§5.3)
}

// route_service.dart
class RouteService {
  static Future<RouteService> create();  // routing.db ロード込みの初期化

  /// 1対1のリアルタイム探索(直線距離ヒューリスティックのA*)
  Future<RouteResult?> findRoute({
    required LatLng from,
    required String shelterId,
    required DisasterMode mode,
    required WeightProfile profile,
  });

  /// 1始点→複数避難所の一括探索(h=0のDijkstra)。事前計算が使う
  Future<List<RouteResult>> findRoutesToAll({
    required LatLng from,
    required DisasterMode mode,
    required WeightProfile profile,
  });

  /// モードに対応した避難所一覧(typesでフィルタ)
  List<ShelterInfo> sheltersFor(DisasterMode mode);
}

// precompute_service.dart
class PrecomputeService {
  /// 自宅登録時に呼ぶ。全モード×全プロファイルを計算しDB保存。
  /// onProgress は 0.0〜1.0
  Future<void> precomputeAll({
    required LatLng home,
    void Function(double progress)? onProgress,
  });

  Future<List<RouteResult>> loadPrecomputed({
    required DisasterMode mode,
    required WeightProfile profile,
  });
}
```

`ShelterInfo` は routing.db の shelters 行のDartモデル(shelterId, name, lat, lon, elevationM, coastDistanceM, types, capacity, nearestNode)。既存 `models/shelter.dart` とは**別クラスとして新設**する(既存モデルはbosai_app.db用のため触らない)。

## 4. データ層

### 4.1 routing.db の展開

- `assets/routing.db` を初回起動時にアプリのドキュメントディレクトリへコピーし、以後はコピー済みを開く
- コピー実装は既存 `map_spike_screen.dart` のPMTilesコピー(rootBundle.load → writeAsBytes)と同一パターンを踏襲
- 読み取り専用で開く(`openDatabase(path, readOnly: true)`)

### 4.2 インメモリグラフ

- 探索中にSQLiteを叩くことを禁止する。起動時(RouteService.create)に nodes/edges を全件読み、以下のフラット構造に展開:
  - `Float64List lat, lon`(ノード)
  - CSR形式の隣接リスト(`Int32List adjOffsets, adjTargets, adjEdgeIds`)。無向エッジは**両方向に展開**
  - エッジ属性: `Float64List lengthM, waterDistM, elevationM` / `Uint8List flags`(bit0=bridge, bit1=tunnel)
  - `geometry` は探索では不要なため**メモリに載せない**。結果構築時に該当エッジのみDBから引く
- OSM node id(int64)→ 内部連番indexのマップを構築し、探索は内部indexで行う

## 5. コスト設計

### 5.1 重みテーブル(初期値。定数クラス `RoutingWeights` に置き、値の差し替えが1箇所で済む構造にする)

ペナルティはすべて非負のメートル換算。

| 項目 | 条件 | earthquake | flood |
|---|---|---:|---:|
| 水域近接(弱) | 50 ≤ water_dist_m < 100 | +100 | +300 |
| 水域近接(強) | water_dist_m < 50(上と排他) | +200 | +600 |
| 橋 | is_bridge | +600 | +300 |
| トンネル/アンダーパス | is_tunnel | +400 | **ハード制約(§5.3)** |
| 低標高 | max(0, 2.0 − elevation_m) × k | k=0 | k=150 |

プロファイル係数(**ペナルティにのみ**乗算、距離には掛けない):
fastest ×0.5 / balanced ×1.0 / safest ×2.0

```
EdgeCost(e) = lengthM + profileFactor × Σ penalty_i(e)
```

### 5.2 モード別の避難所フィルタ

- `sheltersFor(mode)`: shelters.types に基づく
  - earthquake → `earthquake` または `fire` を含む施設
  - flood → `flood` または `surge` を含む施設
- フィルタ結果が0件の場合は全件を返し、警告フラグをログに出す(データ不備でアプリが空にならないための保険)

### 5.3 ハード制約とフォールバック(重要)

- **floodモードでは is_tunnel エッジを探索対象から除外する**(EdgeFilter として実装。コスト無限大ではなく隣接展開時にスキップ)
- 除外の結果ゴールへ到達不能だった場合のみ、**フォールバック探索**を1回だけ行う: is_tunnel を +3000m のソフトペナルティに緩めて再探索し、結果の `usedFallback = true` を立てる
- earthquake モードにハード制約はない(全エッジ通行可、表の重みのみ)

## 6. 探索アルゴリズム

### 6.1 A* 1実装(確定)

- 優先度付きキューによる標準的なA*。`heuristic` が null のとき h=0 で動作(=Dijkstra)
- 複数ゴール対応: `Set<int> goalNodes` を受け、**ゴールノードがsettled(キューから確定)されるたびに記録し、全ゴール確定またはキュー枯渇で終了**。「最初の1件で終了」は禁止
- 複数ゴール探索時は heuristic を必ず null にする(単一ゴール用の直線距離hを複数ゴールに流用しない)
- 単一ゴール時の heuristic: ゴールとの大円距離(haversine)。コストが「実距離+非負ペナルティ」なので admissible / consistent が保たれる。**ヒューリスティックに係数を掛けたり水増ししたりしない**
- 経路復元: cameFrom(先行エッジid)配列から復元し、各エッジの geometry をDBから引いて連結。エッジの向きに応じて座標列を反転すること(連結部の座標一致で検証)

### 6.2 スナップ

- `snap.dart`: 与えられた LatLng に対し全ノードを線形走査して最近傍(haversine)を返す。数万ノードの線形走査は数ms以内であり、ハッカソン範囲ではインデックス不要
- 最近傍距離が300mを超える場合は「グラフ範囲外」としてnullを返し、呼び出し側がエラー表示できるようにする

### 6.3 isolate方針(確定)

- `precomputeAll` と `findRoute` の探索本体は `Isolate.run` で実行する(初回グラフロードも同様)
- isolateへ渡すグラフは §4.2 のフラットTypedData構造をそのまま送る(TypedDataはsendable)。クロージャに大きなオブジェクトをキャプチャしない
- geometry のDB引きはメインisolate側で行う(sqfliteはプラットフォームチャネル依存のため探索isolateから触らない)

## 7. 永続化: precomputed_routes

既存 `bosai_app.db`(database_helper.dart)に以下を追加する。**変更はこの1点のみ**:

- `version: 1` → `version: 2` に上げ、`onUpgrade` で以下を実行。**新規インストール用に `onCreate` にも同じCREATEを追加**:

```sql
CREATE TABLE IF NOT EXISTS precomputed_routes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  shelter_id TEXT NOT NULL,
  disaster_mode TEXT NOT NULL,     -- 'earthquake' | 'flood'
  weight_profile TEXT NOT NULL,    -- 'fastest' | 'balanced' | 'safest'
  distance_m REAL NOT NULL,
  penalty_m REAL NOT NULL,
  est_minutes REAL NOT NULL,
  safety_score REAL NOT NULL,
  used_fallback INTEGER NOT NULL DEFAULT 0,
  geometry TEXT NOT NULL,          -- [[lat,lon],...] JSON
  computed_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_pre_mode_profile
  ON precomputed_routes(disaster_mode, weight_profile);
```

- `precomputeAll` は既存行を全削除(DELETE)してから、**単一トランザクション**で一括insert
- 保存件数 = モード2 × プロファイル3 × 各モードの対象避難所数(到達不能でフォールバックも失敗した避難所はスキップし件数をログ)

## 8. テスト(必須。flutter test で完走すること)

### 8.1 手作りグラフでの正当性(astar_test.dart)

sqflite非依存で `Graph` を直接構築できるコンストラクタを用意し、10ノード程度の格子グラフで:

1. ペナルティ全0のとき、既知の最短経路と距離が一致する
2. 特定エッジの water_dist_m を小さくしてfloodモードで探索すると、そのエッジを回避した経路に変わる
3. 同一の単一ゴール探索で、h=0(Dijkstra)と直線距離hのA*が**同一コスト**の経路を返す
4. 複数ゴール探索で、全ゴールへの経路が返り、各経路コストが個別Dijkstraの結果と一致する
5. floodモードで is_tunnel エッジが唯一の経路のとき、通常探索は失敗し、フォールバックで `usedFallback=true` の経路が返る

### 8.2 コスト関数(cost_function_test.dart)

- 各重み項の境界値(water_dist_m = 49.9 / 50 / 99.9 / 100)で期待ペナルティになる
- プロファイル係数が距離に掛からずペナルティのみに掛かる

### 8.3 実データ疎通(precompute_test.dart、routing.db が無い環境ではskip可能にする)

- 西葛西付近(35.6647, 139.8586)を自宅として precomputeAll が完走し、期待行数が入る

## 9. 受け入れ条件

1. `flutter analyze` エラー0(warning はやむを得ないもののみ)
2. §8 のテストが全て通る
3. 既存機能のコードdiffが database_helper.dart のマイグレーション以外に存在しない
4. 実機/シミュレータで、西葛西付近を自宅とした precomputeAll が10秒以内に完了する(超える場合はボトルネックを計測してREADMEに記録)

## 10. スコープ外(実装するな)

- UI・画面・地図描画・Polyline(仕様書③)
- 広域避難(区外避難)の経路計算 ※floodモードの避難所フィルタで近似し、UI側の注意文言で補う方針(③の範囲)
- 双方向探索、Contraction Hierarchies、強化学習、時間依存コスト
- 液状化属性(routing.dbに列が無いため。将来拡張)
- リアルタイム災害情報の取得
