import Foundation
import GRDB

struct HomeInfo: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "home_info"

    var id: Int = 1
    var building: String
    var floor: Int
    var lat: Double
    var lon: Double
    var coastDistanceM: Double

    enum CodingKeys: String, CodingKey {
        case id, building, floor, lat, lon
        case coastDistanceM = "coast_distance_m"
    }
}
