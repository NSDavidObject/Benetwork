import Foundation

public enum ParsingError: Error {
  case unexpectedType
  case unexpectedValue
  case valueNotFound

  public var localizedDescription: String {
    return "Unexpected response".localized
  }
}
