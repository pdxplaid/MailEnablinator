enum ConnectionTestStatus: Equatable {
    case idle
    case testing
    case success
    case failure(String)
}
