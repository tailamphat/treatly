import Foundation
import TreatlyCore

@MainActor
final class GoogleTasksSource: TaskSource {
    let kind = TaskSourceKind.googleTasks
    /// Google Tasks has no push updates; the app polls.
    var onChange: (() -> Void)?
    private(set) var availableLists: [(id: String, title: String)] = []

    let auth: GoogleAuth
    private let selectedListIDs: () -> Set<String>
    private let base = "https://tasks.googleapis.com/tasks/v1"

    init(auth: GoogleAuth, selectedListIDs: @escaping () -> Set<String>) {
        self.auth = auth
        self.selectedListIDs = selectedListIDs
    }

    var isConnected: Bool { auth.isSignedIn }

    private struct Page<Item: Decodable>: Decodable {
        var items: [Item]?
        var nextPageToken: String?
    }

    private struct TaskList: Decodable { var id: String; var title: String }

    private struct GoogleTask: Decodable {
        var id: String
        var title: String?
        var due: String?
        var status: String?
    }

    func fetch() async throws -> [TaskItem] {
        guard isConnected else { return [] }
        let lists: [TaskList] = try await getAll("\(base)/users/@me/lists?maxResults=100")
        availableLists = lists.map { ($0.id, $0.title) }

        let selected = selectedListIDs()
        var items: [TaskItem] = []
        for list in lists where selected.isEmpty || selected.contains(list.id) {
            let tasks: [GoogleTask] = try await getAll("\(base)/lists/\(Self.pathComponent(list.id))/tasks?showCompleted=false&showHidden=false&maxResults=100")
            for task in tasks where task.status != "completed" {
                let title = task.title?.trimmingCharacters(in: .whitespaces) ?? ""
                guard !title.isEmpty else { continue }
                items.append(TaskItem(
                    source: .googleTasks,
                    sourceID: "\(list.id)|\(task.id)",
                    title: title,
                    dueDate: DueDate.resolve(GoogleTasksDate.components(fromDue: task.due))
                ))
            }
        }
        return items
    }

    func complete(_ task: TaskItem) async throws {
        let ids = task.sourceID.split(separator: "|", maxSplits: 1).map(String.init)
        guard ids.count == 2 else { return }
        guard let url = URL(string: "\(base)/lists/\(Self.pathComponent(ids[0]))/tasks/\(Self.pathComponent(ids[1]))") else { return }
        var request = try await authorized(url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"status":"completed"}"#.utf8)
        _ = try await send(request)
    }

    /// Google Tasks only stores a due date, not a time, so a 10 minute snooze
    /// can't be synced. The local hide is enough.
    func snooze(_ task: TaskItem, until: Date) async throws {}

    /// Ids come from Google, but never let one change the URL's shape.
    private static func pathComponent(_ id: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_")
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private func getAll<Item: Decodable>(_ url: String) async throws -> [Item] {
        var all: [Item] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(string: url)!
            if let pageToken {
                components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "pageToken", value: pageToken)]
            }
            let data = try await send(try await authorized(components.url!))
            let page = try JSONDecoder().decode(Page<Item>.self, from: data)
            all += page.items ?? []
            pageToken = page.nextPageToken
        } while pageToken != nil
        return all
    }

    private func authorized(_ url: URL) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await auth.validAccessToken())", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw GoogleAuthError("Google Tasks request failed (\(status)): \(String(data: data, encoding: .utf8) ?? "")")
        }
        return data
    }
}
