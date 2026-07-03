import SwiftUI

/// 候補カード画面: 1件ずつ表示、YES/NOの2ボタン
struct ShelterCardView: View {
    @ObservedObject var vm: EvacuationViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if let candidate = vm.currentCandidate {
                Text("避難所候補 \(vm.currentShelterIndex + 1)/\(vm.rankedShelters.count)")
                    .font(.headline)
                    .foregroundColor(.secondary)

                VStack(spacing: 16) {
                    Text(candidate.shelter.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 20) {
                        infoColumn(label: "距離", value: formatDistance(candidate.distance))
                        infoColumn(label: "徒歩", value: "\(candidate.walkMinutes)分")
                        infoColumn(label: "海抜", value: String(format: "%.1fm", candidate.shelter.elevationM))
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(16)
                .padding(.horizontal)

                Spacer()

                // YES / NO ボタン
                VStack(spacing: 12) {
                    Button {
                        vm.selectShelter()
                    } label: {
                        Text("ここへ避難する（YES）")
                            .font(.title3)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button {
                        vm.rejectShelter()
                    } label: {
                        Text("NO（次の候補）")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray4))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }

    private func infoColumn(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1fkm", meters / 1000)
        }
        return String(format: "%.0fm", meters)
    }
}
