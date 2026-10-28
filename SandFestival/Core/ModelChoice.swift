import Foundation

nonisolated enum ModelChoice: String, CaseIterable, Identifiable {
    case automatic
    case onDevice
    case agentModel
    case off

    enum Source: Equatable {
        case onDevice
        case agentModel
    }

    var id: String { rawValue }

    func source(onDeviceAvailable: Bool, agentModelAvailable: Bool) -> Source? {
        switch self {
        case .automatic:
            if onDeviceAvailable { return .onDevice }
            return agentModelAvailable ? .agentModel : nil
        case .onDevice:
            return onDeviceAvailable ? .onDevice : nil
        case .agentModel:
            return agentModelAvailable ? .agentModel : nil
        case .off:
            return nil
        }
    }
}
