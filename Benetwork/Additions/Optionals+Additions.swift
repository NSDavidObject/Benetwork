import Foundation

extension Optional {

    public func required(file: String = #file, line: Int = #line, function: String = #function) throws -> Wrapped {
        switch self {
        case .none:
            print("Failed to unwrap required field in \(file.components(separatedBy: "/").last ?? ""):\(line) : \(function)")
            throw ParsingError.valueNotFound
        case .some(let value):
            return value
        }
    }
}
