import SwiftUI

/// 簡易ナビ画面: 方位 + 残距離 + 避難所名（MVPは地図なし）
struct NavigationGuideView: View {
    @ObservedObject var vm: EvacuationViewModel
    // TODO(差し替え): MapProvider経由で地図ビューを表示（担当: メンバーC）
    private let mapProvider = EmptyMapProvider()

    var body: some View {
        VStack(spacing: 20) {
            if let route = vm.selectedRoute {
                Spacer()

                Text("避難先")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text(route.destinationName)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Spacer()

                // 方位表示
                VStack(spacing: 8) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                        .rotationEffect(.degrees(route.bearingDegrees))

                    Text(EvacuationViewModel.bearingToDirection(route.bearingDegrees))
                        .font(.title)
                        .fontWeight(.bold)

                    Text(String(format: "%.0f°", route.bearingDegrees))
                        .font(.title2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 残距離
                VStack(spacing: 4) {
                    Text("残り距離")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(formatDistance(route.distance))
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                    Text("徒歩約\(max(1, Int(ceil(route.distance / 80.0))))分")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // TODO(差し替え): 地図表示エリア（MapProvider差し替え後に有効化）
                mapProvider.mapView(route: route)
                    .frame(height: 0) // MVPでは非表示

                Button {
                    vm.reset()
                } label: {
                    Text("ホームに戻る")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
            }
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}
