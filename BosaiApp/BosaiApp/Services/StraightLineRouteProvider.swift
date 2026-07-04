import Foundation

/// MVP用の直線距離＋方位角ルートプロバイダ
/// // TODO(差し替え): A*経路探索アルゴリズムに差し替え（担当: メンバーB）
final class StraightLineRouteProvider: RouteProvider {
    func route(from: Coordinate, to: Coordinate) -> RouteInfo {
        let distance = haversineDistance(from: from, to: to)
        let bearing = calculateBearing(from: from, to: to)
        return RouteInfo(distance: distance, bearingDegrees: bearing, destinationName: "")
    }

    /// Haversine公式による2点間距離（メートル）
    private func haversineDistance(from: Coordinate, to: Coordinate) -> Double {
        let R = 6371000.0 // 地球半径(m)
        let lat1 = from.lat * .pi / 180
        let lat2 = to.lat * .pi / 180
        let dLat = (to.lat - from.lat) * .pi / 180
        let dLon = (to.lon - from.lon) * .pi / 180

        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    /// 方位角（北=0°, 時計回り）
    private func calculateBearing(from: Coordinate, to: Coordinate) -> Double {
        let lat1 = from.lat * .pi / 180
        let lat2 = to.lat * .pi / 180
        let dLon = (to.lon - from.lon) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}

// MARK: - A* 経路探索

/// オフライン道路ネットワーク上のA*経路探索ルートプロバイダ（担当: メンバーB）
///
/// - グラフデータは外部ファイルに依存せず、Swiftリテラル定数として埋め込む
///   （葛飾区周辺のシード避難所10件とデモ出発点をカバーする簡易ネットワーク）
/// - 出発点・目的地は最寄りノードへスナップし、
///   総距離 = 出発スナップ距離 + A*経路長 + 到着スナップ距離
/// - グラフ範囲外（スナップ上限超過）・経路未発見の場合は
///   StraightLineRouteProvider と同一の結果にフォールバックする（クラッシュさせない）
final class AStarRouteProvider: RouteProvider {

    // MARK: 調整用定数

    /// 出発点・目的地を最寄りノードへ接続（スナップ）できる距離の上限[m]
    private static let maxSnapDistanceM: Double = 300.0

    // MARK: 埋め込みグラフデータ

    /// ノード: 各シード避難所の直近ノード（n_s***）＋デモ経路・接続用ノード
    private static let graphNodes: [(id: String, lat: Double, lon: Double)] = [
        // 避難所直近ノード
        (id: "n_s001", lat: 35.7803, lon: 139.8675),  // 水元公園
        (id: "n_s002", lat: 35.7512, lon: 139.8456),  // 青戸中学校
        (id: "n_s003", lat: 35.7445, lon: 139.8512),  // 新宿小学校
        (id: "n_s004", lat: 35.7568, lon: 139.8389),  // 総合スポーツセンター
        (id: "n_s005", lat: 35.7721, lon: 139.8734),  // 東金町運動場
        (id: "n_s006", lat: 35.7634, lon: 139.8501),  // 亀有中学校
        (id: "n_s007", lat: 35.7678, lon: 139.8612),  // にいじゅくみらい公園
        (id: "n_s008", lat: 35.7389, lon: 139.8234),  // 堀切中学校
        (id: "n_s009", lat: 35.7345, lon: 139.8156),  // 荒川河川敷広場
        (id: "n_s010", lat: 35.7501, lon: 139.8567),  // 高砂小学校
        // Xcodeデモで登録する自宅座標から既存ネットワークまでの接続ノード
        (id: "n_d00", lat: 35.6065, lon: 139.7344),
        (id: "n_d01", lat: 35.6280, lon: 139.7425),
        (id: "n_d02", lat: 35.6500, lon: 139.7535),
        (id: "n_d03", lat: 35.6720, lon: 139.7690),
        (id: "n_d04", lat: 35.6935, lon: 139.7855),
        (id: "n_d05", lat: 35.7145, lon: 139.8010),
        // デフォルト出発点（葛飾区役所付近）直近ノード
        (id: "n_x00", lat: 35.7436, lon: 139.8477),
        // 接続用交差点ノード
        (id: "n_x01", lat: 35.7470, lon: 139.8400),
        (id: "n_x02", lat: 35.7410, lon: 139.8330),
        (id: "n_x03", lat: 35.7370, lon: 139.8195),
        (id: "n_x04", lat: 35.7480, lon: 139.8545),
        (id: "n_x05", lat: 35.7545, lon: 139.8520),
        (id: "n_x06", lat: 35.7570, lon: 139.8460),
        (id: "n_x07", lat: 35.7600, lon: 139.8560),
        (id: "n_x08", lat: 35.7700, lon: 139.8680),
        (id: "n_x09", lat: 35.7760, lon: 139.8700),
    ]

    /// エッジ: 無向。コストは両端ノードのhaversine距離で補完（init時に算出）
    private static let graphEdges: [(from: String, to: String)] = [
        (from: "n_d00", to: "n_d01"),
        (from: "n_d01", to: "n_d02"),
        (from: "n_d02", to: "n_d03"),
        (from: "n_d03", to: "n_d04"),
        (from: "n_d04", to: "n_d05"),
        (from: "n_d05", to: "n_s009"),
        (from: "n_x00", to: "n_s003"),
        (from: "n_x00", to: "n_x01"),
        (from: "n_s003", to: "n_s002"),
        (from: "n_s003", to: "n_x04"),
        (from: "n_x04", to: "n_s010"),
        (from: "n_s002", to: "n_x05"),
        (from: "n_x05", to: "n_s010"),
        (from: "n_x05", to: "n_x06"),
        (from: "n_x06", to: "n_s004"),
        (from: "n_x06", to: "n_s006"),
        (from: "n_s006", to: "n_x07"),
        (from: "n_x07", to: "n_s010"),
        (from: "n_x07", to: "n_s007"),
        (from: "n_s007", to: "n_x08"),
        (from: "n_x08", to: "n_s005"),
        (from: "n_x08", to: "n_s001"),
        (from: "n_s005", to: "n_x09"),
        (from: "n_x09", to: "n_s001"),
        (from: "n_x01", to: "n_s004"),
        (from: "n_x01", to: "n_x02"),
        (from: "n_x02", to: "n_s008"),
        (from: "n_s008", to: "n_x03"),
        (from: "n_x03", to: "n_s009"),
    ]

    // MARK: 内部状態

    private let nodeCoords: [String: Coordinate]
    private let adjacency: [String: [(id: String, lengthM: Double)]]

    /// フォールバック用（既存モックと同一挙動を委譲で保証）
    private let fallbackProvider = StraightLineRouteProvider()

    init() {
        var coords: [String: Coordinate] = [:]
        for node in Self.graphNodes {
            coords[node.id] = Coordinate(lat: node.lat, lon: node.lon)
        }
        var adj: [String: [(id: String, lengthM: Double)]] = [:]
        for node in Self.graphNodes {
            adj[node.id] = []
        }
        for edge in Self.graphEdges {
            guard let a = coords[edge.from], let b = coords[edge.to] else { continue }
            let lengthM = Self.haversineDistance(from: a, to: b)
            adj[edge.from]?.append((id: edge.to, lengthM: lengthM))
            adj[edge.to]?.append((id: edge.from, lengthM: lengthM))
        }
        nodeCoords = coords
        adjacency = adj
    }

    // MARK: RouteProvider

    func route(from: Coordinate, to: Coordinate) -> RouteInfo {
        guard let start = nearestNode(to: from), start.distanceM <= Self.maxSnapDistanceM,
              let goal = nearestNode(to: to), goal.distanceM <= Self.maxSnapDistanceM else {
            return fallbackRoute(from: from, to: to, reason: "スナップ上限超過")
        }

        let pathNodeIds: [String]
        let pathLengthM: Double
        if start.id == goal.id {
            pathNodeIds = [start.id]
            pathLengthM = 0
        } else if let result = astar(from: start.id, to: goal.id) {
            pathNodeIds = result.path
            pathLengthM = result.distanceM
        } else {
            return fallbackRoute(from: from, to: to, reason: "経路未発見")
        }

        let totalDistance = start.distanceM + pathLengthM + goal.distanceM
        let bearing = initialMoveBearing(from: from, pathNodeIds: pathNodeIds, to: to)

        #if DEBUG
        let straight = Self.haversineDistance(from: from, to: to)
        print("[AStarRouteProvider] 直線=\(Int(straight))m A*=\(Int(totalDistance))m 経由ノード数=\(pathNodeIds.count) フォールバック=なし")
        #endif

        return RouteInfo(distance: totalDistance, bearingDegrees: bearing, destinationName: "")
    }

    // MARK: 探索

    /// 最寄りノードのIDとスナップ距離[m]（グラフが空の場合のみnil）
    private func nearestNode(to coord: Coordinate) -> (id: String, distanceM: Double)? {
        var best: (id: String, distanceM: Double)?
        for (id, nodeCoord) in nodeCoords {
            let d = Self.haversineDistance(from: coord, to: nodeCoord)
            if best == nil || d < best!.distanceM {
                best = (id: id, distanceM: d)
            }
        }
        return best
    }

    /// 標準A*。g=経路上のエッジ長合計、h=ゴールノードへのhaversine直線距離（許容的）。
    /// ノード数は数十想定のため、open集合は配列の最小値探索で足りる。
    private func astar(from startId: String, to goalId: String) -> (distanceM: Double, path: [String])? {
        guard let goalCoord = nodeCoords[goalId] else { return nil }

        func heuristic(_ id: String) -> Double {
            guard let c = nodeCoords[id] else { return 0 }
            return Self.haversineDistance(from: c, to: goalCoord)
        }

        var open: [(f: Double, g: Double, id: String, path: [String])] = [
            (f: heuristic(startId), g: 0, id: startId, path: [startId])
        ]
        var bestG: [String: Double] = [:]

        while !open.isEmpty {
            var minIndex = 0
            for i in 1..<open.count where open[i].f < open[minIndex].f {
                minIndex = i
            }
            let current = open.remove(at: minIndex)

            if current.id == goalId {
                return (distanceM: current.g, path: current.path)
            }
            if let known = bestG[current.id], known <= current.g { continue }
            bestG[current.id] = current.g

            for edge in adjacency[current.id] ?? [] {
                let g = current.g + edge.lengthM
                if let known = bestG[edge.id], known <= g { continue }
                open.append((f: g + heuristic(edge.id), g: g, id: edge.id, path: current.path + [edge.id]))
            }
        }
        return nil
    }

    /// 最初の実移動方向（出発点→スナップ先ノード）のinitial bearing。
    /// 出発点がノードとほぼ同一（1m未満）の場合は経路上の次の地点へ、
    /// それも無ければ目的地へのbearingにする（0除算相当の不安定さを避ける）。
    private func initialMoveBearing(from: Coordinate, pathNodeIds: [String], to: Coordinate) -> Double {
        for id in pathNodeIds {
            guard let c = nodeCoords[id] else { continue }
            if Self.haversineDistance(from: from, to: c) >= 1.0 {
                return Self.calculateBearing(from: from, to: c)
            }
        }
        return Self.calculateBearing(from: from, to: to)
    }

    // MARK: フォールバック

    private func fallbackRoute(from: Coordinate, to: Coordinate, reason: String) -> RouteInfo {
        let route = fallbackProvider.route(from: from, to: to)
        #if DEBUG
        print("[AStarRouteProvider] 直線=\(Int(route.distance))m A*=なし 経由ノード数=0 フォールバック=あり(\(reason))")
        #endif
        return route
    }

    // MARK: 地理計算
    // StraightLineRouteProvider の同名メソッドはprivate（型スコープ）のため
    // クラス外から参照できず、同一の式をここに持つ。
    // フォールバック結果の互換性は fallbackProvider への委譲で担保する。

    /// Haversine公式による2点間距離（メートル）
    private static func haversineDistance(from: Coordinate, to: Coordinate) -> Double {
        let R = 6371000.0 // 地球半径(m)
        let lat1 = from.lat * .pi / 180
        let lat2 = to.lat * .pi / 180
        let dLat = (to.lat - from.lat) * .pi / 180
        let dLon = (to.lon - from.lon) * .pi / 180

        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    /// 方位角（北=0°, 時計回り）
    private static func calculateBearing(from: Coordinate, to: Coordinate) -> Double {
        let lat1 = from.lat * .pi / 180
        let lat2 = to.lat * .pi / 180
        let dLon = (to.lon - from.lon) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}
