import SwiftUI
import PhotosUI
import Combine

@MainActor
final class DiagnosisViewModel: ObservableObject {
    // MARK: - 入力
    @Published var selectedPhoto: PhotosPickerItem?
    @Published var selectedImage: UIImage?
    @Published var input = DiagnosisInput()

    // MARK: - 結果
    @Published var result: DiagnosisResult?
    @Published var isDiagnosing = false
    @Published var showResult = false

    // TODO(差し替え): DIコンテナ経由で注入可能にする
    private let engine: DiagnosisEngine = MockDiagnosisEngine()

    // MARK: - 写真読み込み

    func loadImage() async {
        guard let item = selectedPhoto else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let uiImage = UIImage(data: data) {
            selectedImage = uiImage
        }
    }

    // MARK: - 固定具トグル

    func toggleFixture(_ fixture: FixtureType) {
        if fixture == .none {
            // 「固定なし」を選んだら他をクリア
            input.fixtures = [.none]
        } else {
            input.fixtures.remove(.none)
            if input.fixtures.contains(fixture) {
                input.fixtures.remove(fixture)
            } else {
                input.fixtures.insert(fixture)
            }
            if input.fixtures.isEmpty {
                input.fixtures = [.none]
            }
        }
    }

    func isFixtureSelected(_ fixture: FixtureType) -> Bool {
        input.fixtures.contains(fixture)
    }

    // MARK: - 診断実行

    func runDiagnosis() async {
        isDiagnosing = true
        result = await engine.diagnose(image: selectedImage, input: input)
        isDiagnosing = false
        showResult = true
    }

    // MARK: - 履歴保存

    func saveToHistory() {
        guard let result = result else { return }

        // 画像保存（任意）
        var imagePath: String?
        if let image = selectedImage, let data = image.jpegData(compressionQuality: 0.7) {
            let filename = UUID().uuidString + ".jpg"
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(filename)
            try? data.write(to: url)
            imagePath = filename
        }

        let fixturesJSON = try? JSONEncoder().encode(Array(input.fixtures.map(\.rawValue)))
        let fixturesStr = fixturesJSON.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        var history = DiagnosisHistory(
            id: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            imagePath: imagePath,
            seismicIntensity: input.seismicIntensity.rawValue,
            soil: input.soil.rawValue,
            fixtures: fixturesStr,
            building: input.building.rawValue,
            floor: input.floor,
            resultLevel: result.level.rawValue,
            advice: result.advice
        )

        try? AppDatabase.shared.saveDiagnosis(&history)
    }
}
