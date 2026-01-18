import SwiftUI

struct ContentView: View {
    @StateObject private var client = StreamClient()
    @State private var urlString = "wss://echo.websocket.events"

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Stream URL")
                        .font(.headline)
                    TextField("wss://example.com/stream", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    Button(client.isConnected ? "Disconnect" : "Connect") {
                        if client.isConnected {
                            client.disconnect()
                        } else {
                            client.connect(urlString: urlString)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Text(client.status)
                        .font(.subheadline)
                        .foregroundStyle(client.isConnected ? .green : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if client.messages.isEmpty {
                            Text("No messages yet. Connect to start receiving data.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(client.messages.indices, id: \.self) { index in
                                Text(client.messages[index])
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Stream Viewer")
        }
        .onDisappear {
            client.disconnect()
        }
    }
}

#Preview {
    ContentView()
}
