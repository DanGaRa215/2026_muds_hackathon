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
