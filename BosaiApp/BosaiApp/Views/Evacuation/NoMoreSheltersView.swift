import SwiftUI

/// 全候補拒否時の最終画面
struct NoMoreSheltersView: View {
    @ObservedObject var vm: EvacuationViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "mountain.2.fill")
                .font(.system(size: 80))
                .foregroundColor(.orange)

            Text("最寄りの高台へ\n向かってください")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("周囲の安全を確認しながら\nできるだけ高い場所へ避難してください")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                vm.reset()
            } label: {
                Text("ホームに戻る")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}
