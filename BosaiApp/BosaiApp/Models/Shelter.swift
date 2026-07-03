import Foundation
import GRDB

struct Shelter: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "shelters"

    var id: String { shelterId }
    var shelterId: String
    var name: String
    var lat: Double
    var lon: Double
    var elevationM: Double
    var coastDistanceM: Double
    var types: String          // JSON配列: ["earthquake","tsunami","fire"]
    var capacity: Int?
    var isOpenSpace: Bool

    enum Columns: String, ColumnExpression {
        case shelterId = "shelter_id"
        case name, lat, lon
        case elevationM = "elevation_m"
        case coastDistanceM = "coast_distance_m"
        case types, capacity
        case isOpenSpace = "is_open_space"
    }

    enum CodingKeys: String, CodingKey {
        case shelterId = "shelter_id"
        case name, lat, lon
        case elevationM = "elevation_m"
        case coastDistanceM = "coast_distance_m"
        case types, capacity
        case isOpenSpace = "is_open_space"
    }

    // MARK: - Helper

    var typeArray: [String] {
        guard let data = types.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }
}
