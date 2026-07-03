import SwiftUI

struct HomeView: View {
    @State private var showDiagnosis = false
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showEvacuation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Text("防災アプリ")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer()

                VStack(spacing: 16) {
                    NavigationLink(destination: DiagnosisInputView()) {
                        HomeButton(title: "家具診断", icon: "chair.lounge.fill", color: .blue)
                    }

                    NavigationLink(destination: SettingsView()) {
                        HomeButton(title: "避難準備", icon: "house.fill", color: .green)
                    }

                    NavigationLink(destination: HistoryView()) {
                        HomeButton(title: "診断履歴", icon: "clock.fill", color: .orange)
                    }

                    NavigationLink(destination: EvacuationFlowView()) {
                        HomeButton(title: "EEWデモ起動", icon: "exclamationmark.triangle.fill", color: .red)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct HomeButton: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 40)
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Spacer()
            Image(systemName: "chevron.right")
        }
        .foregroundColor(.white)
        .padding()
        .background(color)
        .cornerRadius(12)
    }
}

#Preview {
    HomeView()
}
