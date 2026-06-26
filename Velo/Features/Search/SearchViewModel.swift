import Foundation
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case searching
        case loaded
        case failed(String)
    }

    @Published var query: String = ""
    @Published private(set) var state: State = .idle
    @Published private(set) var results: [LiveStream] = []

    private let repository: StreamsRepository
    private var searchTask: Task<Void, Never>?

    init(repository: StreamsRepository) {
        self.repository = repository
    }

    func scheduleSearch() {
        searchTask?.cancel()

        let query = query
        searchTask = Task {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state = .idle
                results = []
                return
            }

            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state = .idle
            results = []
            return
        }

        state = .searching

        do {
            results = try await repository.search(query: trimmed)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
