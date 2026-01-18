import SwiftUI

struct SavedRunsView: View {
    @ObservedObject var runStore: RunDataStore

    var body: some View {
        List {
            ForEach(runStore.runs) { run in
                NavigationLink(destination: RunAnalysisView(run: run)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(run.name)
                            .font(.headline)
                        Text(run.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Saved runs")
        .onAppear {
            runStore.loadRuns()
        }
    }
}
