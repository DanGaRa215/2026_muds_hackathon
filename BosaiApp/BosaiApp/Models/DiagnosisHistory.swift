import Foundation
import GRDB

struct DiagnosisHistory: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "diagnosis_history"

    var id: Int64?
    var createdAt: String
    var imagePath: String?
    var seismicIntensity: String
    var soil: String
    var fixtures: String       // JSON配列
    var building: String
    var floor: Int
    var resultLevel: String    // safe / warning / danger
    var advice: String

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case imagePath = "image_path"
        case seismicIntensity = "seismic_intensity"
        case soil, fixtures, building, floor
        case resultLevel = "result_level"
        case advice
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Helpers

    var fixtureArray: [String] {
        guard let data = fixtures.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }

    var resultLevelDisplay: String {
        switch resultLevel {
        case "safe": return "安全"
        case "warning": return "要改善"
        case "danger": return "危険"
        default: return resultLevel
        }
    }

    var createdAtDate: Date? {
        let f = ISO8601DateFormatter()
        return f.date(from: createdAt)
    }
}
