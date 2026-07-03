import SwiftUI

struct HistoryView: View {
    @StateObject private var vm = HistoryViewModel()

    var body: some View {
        Group {
            if vm.histories.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("診断履歴がありません")
                        .foregroundColor(.secondary)
                }
            } else {
                List {
                    ForEach(vm.histories) { history in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                resultBadge(history.resultLevel)
                                Spacer()
                                Text(formatDate(history.createdAt))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text("震度: \(history.seismicIntensity) / 土質: \(history.soil) / \(history.building) \(history.floor)階")
                                .font(.subheadline)

                            Text(history.advice)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: vm.delete)
                }
            }
        }
        .navigationTitle("診断履歴")
        .onAppear { vm.load() }
    }

    private func resultBadge(_ level: String) -> some View {
        let (text, color): (String, Color) = {
            switch level {
            case "safe":    return ("安全", .green)
            case "warning": return ("要改善", .orange)
            case "danger":  return ("危険", .red)
            default:        return (level, .gray)
            }
        }()

        return Text(text)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(6)
    }

    private func formatDate(_ isoString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        guard let date = isoFormatter.date(from: isoString) else { return isoString }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
}
