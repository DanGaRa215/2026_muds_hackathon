import Foundation

@MainActor
final class EvacuationViewModel: ObservableObject {
    // MARK: - 画面遷移状態
    enum Phase {
        case idle
        case eewScheduled        // EEW通知スケジュール済み・待機中
        case protect             // 身を守って画面
        case situationCheck      // 状況確認
        case shelterCard         // 候補カード表示
        case navigation          // 簡易ナビ
        case noMoreShelters      // 全候補拒否
    }

    @Published var phase: Phase = .idle
    @Published var situation = SituationCheck()
    @Published var rankedShelters: [(shelter: Shelter, distance: Double, walkMinutes: Int, bearing: Double)] = []
    @Published var currentShelterIndex = 0
    @Published var selectedRoute: RouteInfo?

    private let scorer = ShelterScorer()
    private let routeProvider: RouteProvider = StraightLineRouteProvider()

    // MARK: - EEWデモ起動

    func startEEWDemo() {
        NotificationService.shared.scheduleEEWDemo()
        phase = .eewScheduled

        // 5秒後に自動で「身を守って」画面へ（通知タップの代替）
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) { [weak self] in
            self?.phase = .protect
        }
    }

    // MARK: - 身を守って → 状況確認

    func proceedToSituationCheck() {
        phase = .situationCheck
    }

    // MARK: - 状況確認 → 避難所候補

    func confirmSituation() {
        guard let homeInfo = try? AppDatabase.shared.fetchHomeInfo() else {
            // 自宅情報未登録の場合はデフォルト座標（葛飾区役所付近）
            let defaultCoord = Coordinate(lat: 35.7436, lon: 139.8477)
            rankShelters(from: defaultCoord, coastDistance: 12000)
            return
        }

        let coord = Coordinate(lat: homeInfo.lat, lon: homeInfo.lon)
        rankShelters(from: coord, coastDistance: homeInfo.coastDistanceM)
    }

    private func rankShelters(from coord: Coordinate, coastDistance: Double) {
        let allShelters = (try? AppDatabase.shared.fetchAllShelters()) ?? []
        rankedShelters = scorer.rank(
            shelters: allShelters,
            from: coord,
            coastDistanceM: coastDistance,
            situation: situation
        )
        currentShelterIndex = 0
        phase = .shelterCard
    }

    // MARK: - 候補カード操作

    var currentCandidate: (shelter: Shelter, distance: Double, walkMinutes: Int, bearing: Double)? {
        guard currentShelterIndex < rankedShelters.count else { return nil }
        return rankedShelters[currentShelterIndex]
    }

    func selectShelter() {
        guard let candidate = currentCandidate else { return }
        guard let homeInfo = try? AppDatabase.shared.fetchHomeInfo() else {
            // デフォルト座標からのルート
            let from = Coordinate(lat: 35.7436, lon: 139.8477)
            let to = Coordinate(lat: candidate.shelter.lat, lon: candidate.shelter.lon)
            var route = routeProvider.route(from: from, to: to)
            route = RouteInfo(distance: route.distance, bearingDegrees: route.bearingDegrees, destinationName: candidate.shelter.name)
            selectedRoute = route
            phase = .navigation
            return
        }

        let from = Coordinate(lat: homeInfo.lat, lon: homeInfo.lon)
        let to = Coordinate(lat: candidate.shelter.lat, lon: candidate.shelter.lon)
        var route = routeProvider.route(from: from, to: to)
        route = RouteInfo(distance: route.distance, bearingDegrees: route.bearingDegrees, destinationName: candidate.shelter.name)
        selectedRoute = route
        phase = .navigation
    }

    func rejectShelter() {
        currentShelterIndex += 1
        if currentShelterIndex >= rankedShelters.count {
            phase = .noMoreShelters
        }
    }

    // MARK: - リセット

    func reset() {
        phase = .idle
        situation = SituationCheck()
        rankedShelters = []
        currentShelterIndex = 0
        selectedRoute = nil
    }

    // MARK: - 方位表示ヘルパー

    static func bearingToDirection(_ degrees: Double) -> String {
        let directions = ["北", "北北東", "北東", "東北東", "東", "東南東", "南東", "南南東",
                          "南", "南南西", "南西", "西南西", "西", "西北西", "北西", "北北西"]
        let index = Int(round(degrees / 22.5)) % 16
        return directions[index]
    }
}
