import Foundation
import Combine

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var histories: [DiagnosisHistory] = []

    func load() {
        histories = (try? AppDatabase.shared.fetchDiagnosisHistory()) ?? []
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            let item = histories[index]
            if let id = item.id {
                try? AppDatabase.shared.deleteDiagnosis(id: id)
            }
        }
        load()
    }
}
