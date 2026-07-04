import SwiftUI
import PhotosUI

struct DiagnosisInputView: View {
    @StateObject private var vm = DiagnosisViewModel()

    var body: some View {
        Form {
            // MARK: - 写真選択（任意）
            Section("写真（任意）") {
                PhotosPicker(selection: $vm.selectedPhoto, matching: .images) {
                    Label("写真を選択", systemImage: "photo")
                }
                .onChange(of: vm.selectedPhoto) { _, _ in
                    Task {
                        await vm.loadImage()
                    }
                }

                if let image = vm.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                }
            }

            // MARK: - 想定震度
            Section("想定震度") {
                Picker("震度", selection: $vm.input.seismicIntensity) {
                    ForEach(SeismicIntensity.allCases) { intensity in
                        Text(intensity.rawValue).tag(intensity)
                    }
                }
                .pickerStyle(.segmented)
            }

            // MARK: - 土質
            Section("土質") {
                Picker("土質", selection: $vm.input.soil) {
                    ForEach(SoilType.allCases) { soil in
                        Text(soil.rawValue).tag(soil)
                    }
                }
                .pickerStyle(.segmented)
            }

            // MARK: - 固定状況
            Section("固定状況") {
                ForEach(FixtureType.allCases) { fixture in
                    Button {
                        vm.toggleFixture(fixture)
                    } label: {
                        HStack {
                            Image(systemName: vm.isFixtureSelected(fixture) ? "checkmark.square.fill" : "square")
                                .foregroundColor(vm.isFixtureSelected(fixture) ? .blue : .gray)
                            Text(fixture.rawValue)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }

            // MARK: - 建物構造
            Section("建物構造") {
                Picker("構造", selection: $vm.input.building) {
                    ForEach(BuildingType.allCases) { bldg in
                        Text(bldg.rawValue).tag(bldg)
                    }
                }
                .pickerStyle(.segmented)
            }

            // MARK: - 階数
            Section("階数") {
                Stepper("階数: \(vm.input.floor)階", value: $vm.input.floor, in: 1...50)
            }

            // MARK: - 診断ボタン
            Section {
                Button {
                    Task { await vm.runDiagnosis() }
                } label: {
                    HStack {
                        Spacer()
                        if vm.isDiagnosing {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text("診断する")
                            .fontWeight(.bold)
                        Spacer()
                    }
                }
                .disabled(vm.isDiagnosing)
            }
        }
        .navigationTitle("家具安全診断")
        .navigationDestination(isPresented: $vm.showResult) {
            if let result = vm.result {
                DiagnosisResultView(result: result, vm: vm)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DiagnosisInputView()
    }
}
