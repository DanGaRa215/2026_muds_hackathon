import SwiftUI

/// 地図表示プロバイダのプロトコル
/// MVP: EmptyMapProvider（地図なし、テキスト表示のみ）
/// 将来: MapLibre + PMTiles 実装に差し替え
protocol MapProvider {
    associatedtype MapContent: View
    func mapView(route: RouteInfo?) -> MapContent
}
