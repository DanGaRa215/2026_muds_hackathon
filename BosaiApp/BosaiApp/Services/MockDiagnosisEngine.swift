import UIKit

/// MVP用のルールベース診断エンジン
/// // TODO(差し替え): CoreMLDiagnosisEngine（YOLOv8 → Core ML）に差し替え（担当: メンバーA）
final class MockDiagnosisEngine: DiagnosisEngine {
    func diagnose(image: UIImage?, input: DiagnosisInput) async -> DiagnosisResult {
        // TODO(差し替え): imageを使った実際のML推論をここに実装（メンバーA）

        // 危険度スコア計算: 震度スコア × 土質増幅 × 固定具の最良値 × 建物増幅 × 階数補正
        let intensityScore = Double(input.seismicIntensity.score)
        let soilAmp = input.soil.amplification
        let buildingAmp = input.building.amplification

        // 固定具: 最も効果的な固定具の軽減率を採用（「固定なし」のみなら1.0）
        let fixtureReduction: Double
        if input.fixtures.isEmpty || (input.fixtures.count == 1 && input.fixtures.contains(.none)) {
            fixtureReduction = 1.0
        } else {
            fixtureReduction = input.fixtures
                .filter { $0 != .none }
                .map(\.reductionScore)
                .min() ?? 1.0
        }

        // 階数補正: 2階以上で1階あたり+10%
        let floorAmp = 1.0 + Double(max(0, input.floor - 1)) * 0.1

        let riskScore = intensityScore * soilAmp * fixtureReduction * buildingAmp * floorAmp

        // 閾値で3段階判定
        let level: DiagnosisResult.Level
        let advice: String

        if riskScore < 2.0 {
            level = .safe
            advice = "現在の固定状況で、想定震度に対して比較的安全と判断されます。定期的に固定具の緩みがないか確認してください。"
        } else if riskScore < 3.5 {
            level = .warning
            advice = buildAdvice(input: input)
        } else {
            level = .danger
            advice = "転倒・落下の危険性が高い状態です。早急にL字金具や突っ張り棒で家具を固定し、重い物を低い位置に移動してください。寝室や避難経路上の家具は最優先で対策してください。"
        }

        return DiagnosisResult(level: level, advice: advice)
    }

    private func buildAdvice(input: DiagnosisInput) -> String {
        var tips: [String] = []

        if input.fixtures.contains(.none) || input.fixtures.isEmpty {
            tips.append("家具の固定がされていません。L字金具や突っ張り棒の設置を推奨します")
        }
        if input.soil == .soft {
            tips.append("軟弱地盤のため揺れが増幅されやすい地域です。固定を強化してください")
        }
        if input.building == .wooden {
            tips.append("木造建築は揺れが大きくなりやすいため、追加の固定対策を検討してください")
        }
        if input.floor >= 3 {
            tips.append("高層階は揺れが増幅されます。背の高い家具は特に注意が必要です")
        }

        if tips.isEmpty {
            tips.append("固定具の状態を定期的に確認し、緩みがあれば締め直してください")
        }

        return tips.joined(separator: "。") + "。"
    }
}
