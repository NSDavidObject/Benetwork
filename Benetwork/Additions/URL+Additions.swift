import Foundation

public extension URL {
  
  static func urlWithURLBase(_ base: String, path: String, urlParams: [String: CustomStringConvertible]) throws -> URL {
    let urlString = base + path
    return try urlWithURLString(urlString, urlParams: urlParams)
  }
  
  static func urlWithURLString(_ urlString: String, urlParams: [String: CustomStringConvertible]) throws -> URL {
    func percentEncode(_ original: String) -> String {
      return original.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? ""
    }
    
    var mutableURLString = urlString.last == "?" ? urlString : urlString + "?"
    let sortedURLParams = urlParams.sorted { (lhs, rhs) -> Bool in
      return lhs.key < rhs.key
    }
    for urlParameter in sortedURLParams {
      mutableURLString += "\(percentEncode(urlParameter.key))=\(percentEncode((urlParameter.value).description))&"
    }
    
    guard let constructedURL = URL(string: mutableURLString.trimmingCharacters(in: ["&"])) else {
      throw "Invalid url"
    }
    return constructedURL
  }
}
