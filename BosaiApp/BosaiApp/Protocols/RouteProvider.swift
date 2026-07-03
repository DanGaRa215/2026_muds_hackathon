import Foundation

/// 経路探索プロバイダのプロトコル
/// MVP: StraightLineRouteProvider（直線距離 + 方位角）
/// 将来: A*経路探索に差し替え
protocol RouteProvider {
    func route(from: Coordinate, to: Coordinate) -> RouteInfo
}
