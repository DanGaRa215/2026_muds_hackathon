import Foundation

@MainActor
final class HomeInfoViewModel: ObservableObject {
    @Published var building: BuildingType = .wooden
    @Published var floor: Int = 1
    @Published var latText: String = ""
    @Published var lonText: String = ""
    @Published var coastDistanceText: String = ""
    @Published var isSaved = false

    func load() {
        guard let info = try? AppDatabase.shared.fetchHomeInfo() else { return }
        building = BuildingType(rawValue: info.building) ?? .wooden
        floor = info.floor
        latText = String(info.lat)
        lonText = String(info.lon)
        coastDistanceText = String(info.coastDistanceM)
    }

    func save() {
        guard let lat = Double(latText),
              let lon = Double(lonText),
              let coastDist = Double(coastDistanceText) else { return }

        let info = HomeInfo(
            id: 1,
            building: building.rawValue,
            floor: floor,
            lat: lat,
            lon: lon,
            coastDistanceM: coastDist
        )

        try? AppDatabase.shared.saveHomeInfo(info)
        isSaved = true
    }
}
