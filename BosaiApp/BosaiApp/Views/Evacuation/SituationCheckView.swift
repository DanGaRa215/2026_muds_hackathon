import SwiftUI

/// 状況確認画面: チェックボックス4項目 + 確認ボタンのみ
struct SituationCheckView: View {
    @ObservedObject var vm: EvacuationViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("状況を確認してください")
                .font(.title)
                .fontWeight(.bold)

            VStack(spacing: 16) {
                checkItem(
                    title: "けがをした",
                    isOn: $vm.situation.isInjured
                )
                checkItem(
                    title: "火災が見える",
                    isOn: $vm.situation.seeFire
                )
                checkItem(
                    title: "建物が傾いている・倒壊",
                    isOn: $vm.situation.buildingDamaged
                )
                checkItem(
                    title: "津波警報を聞いた・沿岸部にいる",
                    isOn: $vm.situation.tsunamiWarning
                )
            }
            .padding(.horizontal)

            Spacer()

            Button {
                vm.confirmSituation()
            } label: {
                Text("確認")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    private func checkItem(title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundColor(isOn.wrappedValue ? .red : .gray)
                Text(title)
                    .font(.title3)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding()
            .background(isOn.wrappedValue ? Color.red.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}
