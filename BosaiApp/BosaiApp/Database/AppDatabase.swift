import Foundation
import GRDB

/// アプリ全体のデータベースマネージャ
final class AppDatabase {
    static let shared = AppDatabase()

    let dbQueue: DatabaseQueue

    private init() {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbURL = appSupportURL.appendingPathComponent("bosai.sqlite")
            dbQueue = try DatabaseQueue(path: dbURL.path)
            try migrator.migrate(dbQueue)
            try seedIfNeeded(dbQueue)
        } catch {
            fatalError("Database setup failed: \(error)")
        }
    }

    // MARK: - マイグレーション

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "shelters") { t in
                t.column("shelter_id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("lat", .double).notNull()
                t.column("lon", .double).notNull()
                t.column("elevation_m", .double).notNull()
                t.column("coast_distance_m", .double).notNull()
                t.column("types", .text).notNull()
                t.column("capacity", .integer)
                t.column("is_open_space", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "diagnosis_history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("created_at", .text).notNull()
                t.column("image_path", .text)
                t.column("seismic_intensity", .text).notNull()
                t.column("soil", .text).notNull()
                t.column("fixtures", .text).notNull()
                t.column("building", .text).notNull()
                t.column("floor", .integer).notNull()
                t.column("result_level", .text).notNull()
                t.column("advice", .text).notNull()
            }

            try db.create(table: "home_info") { t in
                t.column("id", .integer).primaryKey()
                t.column("building", .text).notNull()
                t.column("floor", .integer).notNull()
                t.column("lat", .double).notNull()
                t.column("lon", .double).notNull()
                t.column("coast_distance_m", .double).notNull()
            }
        }

        return migrator
    }

    // MARK: - シードデータ（初回のみ）

    private func seedIfNeeded(_ db: DatabaseQueue) throws {
        try db.write { db in
            let count = try Shelter.fetchCount(db)
            guard count == 0 else { return }

            // 東京都葛飾区周辺のダミー避難所10件
            let shelters: [Shelter] = [
                Shelter(shelterId: "S001", name: "葛飾区立水元公園", lat: 35.7803, lon: 139.8675,
                        elevationM: 2.5, coastDistanceM: 15000, types: "[\"earthquake\"]",
                        capacity: 5000, isOpenSpace: true),
                Shelter(shelterId: "S002", name: "葛飾区立青戸中学校", lat: 35.7512, lon: 139.8456,
                        elevationM: 3.0, coastDistanceM: 12000, types: "[\"earthquake\",\"fire\"]",
                        capacity: 800, isOpenSpace: false),
                Shelter(shelterId: "S003", name: "葛飾区立新宿小学校", lat: 35.7445, lon: 139.8512,
                        elevationM: 2.8, coastDistanceM: 11000, types: "[\"earthquake\"]",
                        capacity: 600, isOpenSpace: false),
                Shelter(shelterId: "S004", name: "葛飾区総合スポーツセンター", lat: 35.7568, lon: 139.8389,
                        elevationM: 4.0, coastDistanceM: 13000, types: "[\"earthquake\",\"tsunami\",\"fire\"]",
                        capacity: 2000, isOpenSpace: true),
                Shelter(shelterId: "S005", name: "東金町運動場", lat: 35.7721, lon: 139.8734,
                        elevationM: 3.2, coastDistanceM: 14000, types: "[\"earthquake\",\"fire\"]",
                        capacity: 3000, isOpenSpace: true),
                Shelter(shelterId: "S006", name: "葛飾区立亀有中学校", lat: 35.7634, lon: 139.8501,
                        elevationM: 3.5, coastDistanceM: 13500, types: "[\"earthquake\"]",
                        capacity: 700, isOpenSpace: false),
                Shelter(shelterId: "S007", name: "葛飾にいじゅくみらい公園", lat: 35.7678, lon: 139.8612,
                        elevationM: 5.0, coastDistanceM: 14500, types: "[\"earthquake\",\"tsunami\"]",
                        capacity: 4000, isOpenSpace: true),
                Shelter(shelterId: "S008", name: "葛飾区立堀切中学校", lat: 35.7389, lon: 139.8234,
                        elevationM: 2.0, coastDistanceM: 10000, types: "[\"earthquake\"]",
                        capacity: 500, isOpenSpace: false),
                Shelter(shelterId: "S009", name: "荒川河川敷広場（葛飾側）", lat: 35.7345, lon: 139.8156,
                        elevationM: 6.5, coastDistanceM: 9500, types: "[\"earthquake\",\"tsunami\",\"fire\"]",
                        capacity: 10000, isOpenSpace: true),
                Shelter(shelterId: "S010", name: "葛飾区立高砂小学校", lat: 35.7501, lon: 139.8567,
                        elevationM: 2.2, coastDistanceM: 11500, types: "[\"earthquake\"]",
                        capacity: 550, isOpenSpace: false),
            ]

            for shelter in shelters {
                try shelter.insert(db)
            }
        }
    }

    // MARK: - 避難所

    func fetchAllShelters() throws -> [Shelter] {
        try dbQueue.read { db in
            try Shelter.fetchAll(db)
        }
    }

    // MARK: - 診断履歴

    func saveDiagnosis(_ history: inout DiagnosisHistory) throws {
        try dbQueue.write { db in
            try history.insert(db)
        }
    }

    func fetchDiagnosisHistory() throws -> [DiagnosisHistory] {
        try dbQueue.read { db in
            try DiagnosisHistory.order(Column("created_at").desc).fetchAll(db)
        }
    }

    func deleteDiagnosis(id: Int64) throws {
        try dbQueue.write { db in
            _ = try DiagnosisHistory.deleteOne(db, id: id)
        }
    }

    // MARK: - 自宅情報

    func saveHomeInfo(_ info: HomeInfo) throws {
        try dbQueue.write { db in
            try info.save(db)
        }
    }

    func fetchHomeInfo() throws -> HomeInfo? {
        try dbQueue.read { db in
            try HomeInfo.fetchOne(db)
        }
    }
}
