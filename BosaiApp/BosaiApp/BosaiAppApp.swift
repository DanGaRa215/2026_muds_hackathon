import SwiftUI

@main
struct BosaiAppApp: App {
    init() {
        // データベース初期化（シードデータ投入含む）
        _ = AppDatabase.shared

        // 通知権限リクエスト
        NotificationService.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
