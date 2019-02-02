import Foundation

public protocol Logger {
    static var name: String { get }
}

public extension Logger {
    static var isEnabled: Bool {
        return ProcessInfo.processInfo.arguments.contains("\(name)LogsEnabled-YES")
    }

    static func log(_ text: String) {
        guard isEnabled else { return }
        print("\(name): \(text)")
    }
}
