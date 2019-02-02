import Foundation

public enum ParsingError: Error {
    case unexpectedType
    case unexpectedValue
    case valueNotFound
}
