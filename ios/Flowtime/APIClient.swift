import Foundation

actor FlowtimeAPI {
    static let shared = FlowtimeAPI()
    var baseURL = URL(string: "https://flowtime.example.com")!

    func sync(task: FlowTask) async throws {
        var request = URLRequest(url: baseURL.appending(path: "api/sync"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SyncEnvelope(action: "upsert-task", payload: task))
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
    }
}

private struct SyncEnvelope<Payload: Encodable>: Encodable {
    let action: String
    let payload: Payload
}
