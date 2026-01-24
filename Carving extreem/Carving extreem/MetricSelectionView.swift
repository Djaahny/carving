import SwiftUI

struct MetricSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var metricStore: MetricSelectionStore

    var body: some View {
        NavigationStack {
            List {
                Section("Live metrics") {
                    ForEach(MetricKind.allCases.filter { $0.category == .live }) { metric in
                        Toggle(metric.title, isOn: binding(for: metric, in: $metricStore.liveMetrics))
                    }
                }

                Section("Recording metrics") {
                    ForEach(MetricKind.allCases.filter { $0.category == .recording }) { metric in
                        Toggle(metric.title, isOn: binding(for: metric, in: $metricStore.recordingMetrics))
                    }
                }
            }
            .navigationTitle("Metrics")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        metricStore.liveMetrics = MetricKind.defaultLiveSelection
                        metricStore.recordingMetrics = MetricKind.defaultRecordingSelection
                    }
                }
            }
        }
    }

    private func binding(for metric: MetricKind, in selection: Binding<Set<MetricKind>>) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(metric) },
            set: { isSelected in
                if isSelected {
                    selection.wrappedValue.insert(metric)
                } else {
                    selection.wrappedValue.remove(metric)
                }
            }
        )
    }
}
