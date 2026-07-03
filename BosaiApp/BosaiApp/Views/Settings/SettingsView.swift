import SwiftUI

/// 避難準備（自宅情報入力）画面
struct SettingsView: View {
    @StateObject private var vm = HomeInfoViewModel()

    var body: some View {
        Form {
            Section("建物構造") {
                Picker("構造", selection: $vm.building) {
                    ForEach(BuildingType.allCases) { bldg in
                        Text(bldg.rawValue).tag(bldg)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("階数") {
                Stepper("階数: \(vm.floor)階", value: $vm.floor, in: 1...50)
            }

            Section("自宅の座標") {
                TextField("緯度（例: 35.7436）", text: $vm.latText)
                    .keyboardType(.decimalPad)
                TextField("経度（例: 139.8477）", text: $vm.lonText)
                    .keyboardType(.decimalPad)
            }

            Section("海岸からの距離") {
                TextField("海岸距離（m）（例: 12000）", text: $vm.coastDistanceText)
                    .keyboardType(.numberPad)
            }

            Section {
                Button {
                    vm.save()
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: vm.isSaved ? "checkmark.circle.fill" : "square.and.arrow.down")
                        Text(vm.isSaved ? "保存しました" : "保存")
                            .fontWeight(.bold)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("避難準備")
        .onAppear { vm.load() }
        .onChange(of: vm.building) { vm.isSaved = false }
        .onChange(of: vm.floor) { vm.isSaved = false }
        .onChange(of: vm.latText) { vm.isSaved = false }
        .onChange(of: vm.lonText) { vm.isSaved = false }
        .onChange(of: vm.coastDistanceText) { vm.isSaved = false }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
