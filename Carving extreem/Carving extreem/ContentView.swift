//
//  ContentView.swift
//  Carving extreem
//
//  Created by Morten Kirkelund on 18/01/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var client = StreamClient()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("BLE Stream")
                        .font(.headline)
                    Text("Device: Carving-Extreem · 100 Hz CSV")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button(client.isConnected ? "Disconnect" : "Connect") {
                        if client.isConnected {
                            client.disconnect()
                        } else {
                            client.connect()
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
                            Text("No BLE data yet. Connect to start streaming from the ESP32.")
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
