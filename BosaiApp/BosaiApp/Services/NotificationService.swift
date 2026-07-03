import UserNotifications

/// ローカル通知管理
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    /// 通知権限をリクエスト
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("通知権限エラー: \(error.localizedDescription)")
            }
        }
    }

    /// EEWデモ用ローカル通知を5秒後に発火
    func scheduleEEWDemo() {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ 緊急地震速報"
        content.body = "強い揺れに備えてください。身を守る行動をとってください。"
        // TODO(差し替え): 実際のEEW警報音に差し替え
        content.sound = .default
        content.categoryIdentifier = "EEW_DEMO"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "eew_demo", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("通知スケジュールエラー: \(error.localizedDescription)")
            }
        }
    }
}
