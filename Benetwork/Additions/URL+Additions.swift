import Foundation

public extension URL {
  
  static func urlWithURLBase(_ base: String, path: String, urlParams: [String: CustomStringConvertible]) -> URL {
    let urlString = base + path
    return urlWithURLString(urlString, urlParams: urlParams)
  }
  
  static func urlWithURLString(_ urlString: String, urlParams: [String: CustomStringConvertible]) -> URL {
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
    
    guard let constructedURL = URL(string: mutableURLString.trimmingCharacters(in: ["&"])) else { fatalError() }
    return constructedURL
  }
}
