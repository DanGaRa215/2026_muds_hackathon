import SwiftUI

/// MVP用の空の地図プロバイダ（テキスト表示のみ）
/// // TODO(差し替え): MapLibre + PMTiles実装に差し替え（担当: メンバーC）
final class EmptyMapProvider: MapProvider {
    func mapView(route: RouteInfo?) -> some View {
        // TODO(差し替え): MapLibre地図ビューに差し替え
        VStack {
            Image(systemName: "map")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("地図は後日実装予定")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
