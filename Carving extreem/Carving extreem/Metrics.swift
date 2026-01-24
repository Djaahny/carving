import Combine
import Foundation

enum MetricCategory {
    case live
    case recording
}

enum MetricKind: String, CaseIterable, Identifiable, Codable {
    case liveCurrentEdge
    case liveLeftEdge
    case liveRightEdge
    case livePeakEdge
    case liveEdgeRate
    case liveSpeed
    case liveTurnCount
    case liveTurnSignal
    case livePitch
    case liveRoll
    case liveAccelG
    case liveLeftRightDelta
    case recordingMaxSpeed
    case recordingAverageSpeed
    case recordingRunDuration
    case recordingDistance
    case recordingTurnCount
    case recordingAverageTurnDuration
    case recordingMaxEdge
    case recordingAverageEdge
    case recordingPeakLeftEdge
    case recordingPeakRightEdge
    case recordingEdgeSampleCount
    case recordingEdgeSampleRate
    case recordingEdgeRate
    case recordingTurnSymmetry
    case recordingBalanceScore

    var id: String { rawValue }

    var category: MetricCategory {
        switch self {
        case .liveCurrentEdge,
             .liveLeftEdge,
             .liveRightEdge,
             .livePeakEdge,
             .liveEdgeRate,
             .liveSpeed,
             .liveTurnCount,
             .liveTurnSignal,
             .livePitch,
             .liveRoll,
             .liveAccelG,
             .liveLeftRightDelta:
            return .live
        case .recordingMaxSpeed,
             .recordingAverageSpeed,
             .recordingRunDuration,
             .recordingDistance,
             .recordingTurnCount,
             .recordingAverageTurnDuration,
             .recordingMaxEdge,
             .recordingAverageEdge,
             .recordingPeakLeftEdge,
             .recordingPeakRightEdge,
             .recordingEdgeSampleCount,
             .recordingEdgeSampleRate,
             .recordingEdgeRate,
             .recordingTurnSymmetry,
             .recordingBalanceScore:
            return .recording
        }
    }

    var title: String {
        switch self {
        case .liveCurrentEdge:
            return "Current edge"
        case .liveLeftEdge:
            return "Left edge"
        case .liveRightEdge:
            return "Right edge"
        case .livePeakEdge:
            return "Peak edge (10s)"
        case .liveEdgeRate:
            return "Edge rate"
        case .liveSpeed:
            return "Speed"
        case .liveTurnCount:
            return "Turns"
        case .liveTurnSignal:
            return "Turn signal"
        case .livePitch:
            return "Pitch"
        case .liveRoll:
            return "Roll"
        case .liveAccelG:
            return "G-force"
        case .liveLeftRightDelta:
            return "Edge delta"
        case .recordingMaxSpeed:
            return "Max speed"
        case .recordingAverageSpeed:
            return "Avg speed"
        case .recordingRunDuration:
            return "Run time"
        case .recordingDistance:
            return "Distance"
        case .recordingTurnCount:
            return "Turns"
        case .recordingAverageTurnDuration:
            return "Avg turn time"
        case .recordingMaxEdge:
            return "Peak edge"
        case .recordingAverageEdge:
            return "Avg edge"
        case .recordingPeakLeftEdge:
            return "Peak left"
        case .recordingPeakRightEdge:
            return "Peak right"
        case .recordingEdgeSampleCount:
            return "Edge samples"
        case .recordingEdgeSampleRate:
            return "Sample rate"
        case .recordingEdgeRate:
            return "Edge rate"
        case .recordingTurnSymmetry:
            return "Turn symmetry"
        case .recordingBalanceScore:
            return "Balance score"
        }
    }

    var detail: String? {
        switch self {
        case .liveEdgeRate, .recordingEdgeRate:
            return "deg/s"
        case .liveAccelG:
            return "g"
        default:
            return nil
        }
    }

    static var defaultLiveSelection: Set<MetricKind> {
        [
            .liveCurrentEdge,
            .livePeakEdge,
            .liveSpeed,
            .liveTurnCount,
            .liveEdgeRate,
            .liveAccelG,
            .livePitch,
            .liveRoll
        ]
    }

    static var defaultRecordingSelection: Set<MetricKind> {
        [
            .recordingMaxSpeed,
            .recordingAverageSpeed,
            .recordingRunDuration,
            .recordingDistance,
            .recordingTurnCount,
            .recordingAverageTurnDuration,
            .recordingMaxEdge,
            .recordingAverageEdge,
            .recordingEdgeSampleRate,
            .recordingEdgeSampleCount,
            .recordingEdgeRate,
            .recordingTurnSymmetry,
            .recordingBalanceScore
        ]
    }
}

@MainActor
final class MetricSelectionStore: ObservableObject {
    @Published var liveMetrics: Set<MetricKind> {
        didSet {
            persist(liveMetrics, key: liveKey)
        }
    }
    @Published var recordingMetrics: Set<MetricKind> {
        didSet {
            persist(recordingMetrics, key: recordingKey)
        }
    }

    private let liveKey = "metricSelection.live"
    private let recordingKey = "metricSelection.recording"

    init() {
        liveMetrics = MetricSelectionStore.load(key: liveKey) ?? MetricKind.defaultLiveSelection
        recordingMetrics = MetricSelectionStore.load(key: recordingKey) ?? MetricKind.defaultRecordingSelection
    }

    private func persist(_ metrics: Set<MetricKind>, key: String) {
        let rawValues = metrics.map(\.rawValue)
        UserDefaults.standard.set(rawValues, forKey: key)
    }

    private static func load(key: String) -> Set<MetricKind>? {
        guard let rawValues = UserDefaults.standard.array(forKey: key) as? [String] else { return nil }
        let metrics = rawValues.compactMap { MetricKind(rawValue: $0) }
        return Set(metrics)
    }
}
