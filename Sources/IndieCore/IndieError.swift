import Foundation

public enum IndieError: Error, LocalizedError, Sendable, Equatable {
    case invalidArgument(String)
    case invalidData(String)
    case unsupported(String)
    case securityViolation(String)
    case notFound(String)
    case processFailed(executable: String, status: Int32, stderr: String)
    case timedOut(String)
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArgument(let message): message
        case .invalidData(let message): message
        case .unsupported(let message): message
        case .securityViolation(let message): message
        case .notFound(let message): message
        case .processFailed(let executable, let status, let stderr):
            "\(executable) 退出，状态码 \(status)：\(stderr)"
        case .timedOut(let operation): "操作超时：\(operation)"
        case .database(let message): "数据库错误：\(message)"
        }
    }
}
