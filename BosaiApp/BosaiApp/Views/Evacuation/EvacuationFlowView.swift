import SwiftUI

/// 避難フロー全体を管理するコンテナビュー
struct EvacuationFlowView: View {
    @StateObject private var vm = EvacuationViewModel()

    var body: some View {
        Group {
            switch vm.phase {
            case .idle:
                EEWStartView(vm: vm)
            case .eewScheduled:
                EEWWaitingView()
            case .protect:
                ProtectView(vm: vm)
            case .situationCheck:
                SituationCheckView(vm: vm)
            case .shelterCard:
                ShelterCardView(vm: vm)
            case .navigation:
                NavigationGuideView(vm: vm)
            case .noMoreShelters:
                NoMoreSheltersView(vm: vm)
            }
        }
        .navigationBarBackButtonHidden(vm.phase != .idle)
    }
}

// MARK: - EEWデモ起動画面

struct EEWStartView: View {
    @ObservedObject var vm: EvacuationViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)

            Text("EEWデモ")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("ボタンを押すと5秒後に\n緊急地震速報の通知が届きます")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button {
                vm.startEEWDemo()
            } label: {
                Text("EEWデモを起動")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .navigationTitle("EEWデモ")
    }
}

// MARK: - EEW待機中

struct EEWWaitingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(2)
            Text("通知を待っています...")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("5秒後に通知が届きます")
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - 身を守って画面（全画面・黒背景）

struct ProtectView: View {
    @ObservedObject var vm: EvacuationViewModel
    @State private var timeRemaining = 10

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                Text("身を守って！")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)

                Text("頭を守り、机の下に\n身を隠してください")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)

                Text("\(timeRemaining)")
                    .font(.system(size: 80, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)

                Spacer()

                Text("タップで次へ進む")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .onTapGesture {
            vm.proceedToSituationCheck()
        }
        .onReceive(timer) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                vm.proceedToSituationCheck()
            }
        }
    }
}

#Preview {
    NavigationStack {
        EvacuationFlowView()
    }
}
