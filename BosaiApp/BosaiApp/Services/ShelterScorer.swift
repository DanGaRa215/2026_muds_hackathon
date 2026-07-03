import Foundation

/// 状況確認の結果
struct SituationCheck {
    var isInjured: Bool = false
    var seeFire: Bool = false
    var buildingDamaged: Bool = false
    var tsunamiWarning: Bool = false
}

/// 避難所スコアリング・順位付け
final class ShelterScorer {
    private let routeProvider: RouteProvider

    init(routeProvider: RouteProvider = StraightLineRouteProvider()) {
        self.routeProvider = routeProvider
    }

    /// 避難所を状況に応じてスコアリングし、上位5件を返す
    func rank(
        shelters: [Shelter],
        from homeCoord: Coordinate,
        coastDistanceM: Double,
        situation: SituationCheck
    ) -> [(shelter: Shelter, distance: Double, walkMinutes: Int, bearing: Double)] {

        let needTsunamiPriority = situation.tsunamiWarning || coastDistanceM < 2000
        let needOpenSpace = situation.seeFire || situation.buildingDamaged

        var scored: [(shelter: Shelter, distance: Double, score: Double, bearing: Double)] = []

        for shelter in shelters {
            let shelterCoord = Coordinate(lat: shelter.lat, lon: shelter.lon)
            let routeInfo = routeProvider.route(from: homeCoord, to: shelterCoord)
            let distance = routeInfo.distance

            var score: Double = 0

            if needTsunamiPriority {
                // 津波優先: 海抜と海岸距離を重視
                score += shelter.elevationM * 1000   // 海抜が高いほど高スコア
                score += shelter.coastDistanceM       // 海岸から遠いほど高スコア
                score -= distance * 0.1               // 距離は軽い減点のみ
            } else {
                // 通常: 距離近い順
                score = -distance  // 距離が近いほど高スコア
            }

            if needOpenSpace && shelter.isOpenSpace {
                score += 5000  // 広域避難場所を優先
            }

            scored.append((shelter: shelter, distance: distance, score: score, bearing: routeInfo.bearingDegrees))
        }

        // スコア降順でソート
        scored.sort { $0.score > $1.score }

        // 上位5件を返す
        return Array(scored.prefix(5)).map { item in
            let walkMinutes = max(1, Int(ceil(item.distance / 80.0)))  // 80m/分
            return (shelter: item.shelter, distance: item.distance, walkMinutes: walkMinutes, bearing: item.bearing)
        }
    }
}
