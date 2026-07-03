import SwiftUI

struct DiagnosisResultView: View {
    let result: DiagnosisResult
    @ObservedObject var vm: DiagnosisViewModel
    @State private var saved = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - 評価結果
                VStack(spacing: 12) {
                    resultIcon
                        .font(.system(size: 80))

                    Text(result.level.display)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(resultColor)
                }
                .padding(.top, 20)

                // MARK: - 参考値ラベル（常時表示・必須）
                Text("※この結果は参考値です")
                    .font(.headline)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)

                // MARK: - アドバイス
                VStack(alignment: .leading, spacing: 8) {
                    Text("アドバイス")
                        .font(.headline)
                    Text(result.advice)
                        .font(.body)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)

                // MARK: - この診断でわからないこと（常時表示・必須）
                VStack(alignment: .leading, spacing: 8) {
                    Text("この診断でわからないこと")
                        .font(.headline)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        bulletPoint("床の材質・摩擦係数")
                        bulletPoint("家具の中身の重量・重心位置")
                        bulletPoint("壁の下地の強度")
                        bulletPoint("家具と壁の間の隙間")
                        bulletPoint("家具の経年劣化の程度")
                        bulletPoint("周囲の家具との干渉")
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)

                // MARK: - 保存ボタン
                Button {
                    vm.saveToHistory()
                    saved = true
                } label: {
                    HStack {
                        Image(systemName: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                        Text(saved ? "保存しました" : "診断結果を保存")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(saved ? Color.green : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(saved)
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
        }
        .navigationTitle("診断結果")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private var resultIcon: Image {
        switch result.level {
        case .safe:    return Image(systemName: "checkmark.shield.fill")
        case .warning: return Image(systemName: "exclamationmark.triangle.fill")
        case .danger:  return Image(systemName: "xmark.octagon.fill")
        }
    }

    private var resultColor: Color {
        switch result.level {
        case .safe:    return .green
        case .warning: return .orange
        case .danger:  return .red
        }
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("・")
            Text(text)
        }
        .font(.subheadline)
    }
}
