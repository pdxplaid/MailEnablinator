enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case idle
    case processing
    case error(String)
}
