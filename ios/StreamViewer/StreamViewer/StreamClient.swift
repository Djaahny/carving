import Foundation

@MainActor
final class StreamClient: ObservableObject {
    @Published private(set) var messages: [String] = []
    @Published private(set) var isConnected = false
    @Published private(set) var status = "Disconnected"

    private var task: URLSessionWebSocketTask?

    func connect(urlString: String) {
        guard let url = URL(string: urlString) else {
            status = "Invalid URL"
            return
        }

        disconnect()
        let session = URLSession(configuration: .default)
        let webSocketTask = session.webSocketTask(with: url)
        task = webSocketTask
        webSocketTask.resume()
        isConnected = true
        status = "Connected"
        receiveNext()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        if isConnected {
            status = "Disconnected"
        }
        isConnected = false
    }

    private func receiveNext() {
        guard let task else { return }
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.appendMessage(text)
                    case .data(let data):
                        let text = String(decoding: data, as: UTF8.self)
                        self.appendMessage(text)
                    @unknown default:
                        self.appendMessage("Received unsupported message")
                    }
                    if self.isConnected {
                        self.receiveNext()
                    }
                case .failure(let error):
                    self.status = "Error: \(error.localizedDescription)"
                    self.isConnected = false
                    self.task = nil
                }
            }
        }
    }

    private func appendMessage(_ message: String) {
        messages.append(message)
        let maxMessages = 200
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }
}
