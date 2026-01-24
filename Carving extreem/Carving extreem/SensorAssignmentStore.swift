import Combine
import Foundation
import SwiftUI

@MainActor
final class SensorAssignmentStore: ObservableObject {
    @AppStorage("sensorAssignment.leftIdentifier") private var leftIdentifier: String = ""
    @AppStorage("sensorAssignment.rightIdentifier") private var rightIdentifier: String = ""

    var leftSensorIdentifier: String? {
        leftIdentifier.isEmpty ? nil : leftIdentifier
    }

    var rightSensorIdentifier: String? {
        rightIdentifier.isEmpty ? nil : rightIdentifier
    }

    func assign(side: SensorSide, identifier: String) {
        switch side {
        case .left:
            leftIdentifier = identifier
        case .right:
            rightIdentifier = identifier
        case .single:
            leftIdentifier = identifier
            rightIdentifier = ""
        }
    }

    func clear() {
        leftIdentifier = ""
        rightIdentifier = ""
    }
}
