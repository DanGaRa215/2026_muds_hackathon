import UIKit

/// 家具安全診断エンジンのプロトコル
/// MVP: MockDiagnosisEngine（ルールベース）
/// 将来: CoreMLDiagnosisEngine（YOLOv8 → Core ML）に差し替え
protocol DiagnosisEngine {
    func diagnose(image: UIImage?, input: DiagnosisInput) async -> DiagnosisResult
}
