import Foundation

#if DEBUG

public class NetworkRequestsCacher {

  public static let shared: NetworkRequestsCacher = NetworkRequestsCacher()
  public var isOn: Bool = false

  private let queue: DispatchQueue = DispatchQueue(label: "network-requests-cacher", qos: .background, attributes: .concurrent, autoreleaseFrequency: .inherit, target: .global())
  private var rateLimiter: TimedLimiter = TimedLimiter(limit: 0.3)
  private var isPendingPersistenceOnDisc: Bool = false {
    didSet {
      if isPendingPersistenceOnDisc {
        rateLimiter.execute({ [weak self] in self?.persistDataOnDiscIfPossible() }, onQueue: queue)
      }
    }
  }

  private var cache: [CacheKey: Data] = NetworkRequestsCacher.persistedCache ?? [:] {
    didSet {
      isPendingPersistenceOnDisc = true
    }
  }

  public func cache(urlRequest: URLRequest, data: Data) {
    cache[CacheKey(urlRequest: urlRequest)] = data
  }

  public func dumpCache() {
    cache = [:]
  }

  public func data(for urlRequest: URLRequest) -> Data? {
    return cache[CacheKey(urlRequest: urlRequest)]
  }
}

fileprivate extension NetworkRequestsCacher {

  private func persistDataOnDiscIfPossible() {
    let data = NSKeyedArchiver.archivedData(withRootObject: cache)
    try? data.write(to: NetworkRequestsCacher.fileWriteURL)
  }

  static var persistedCache: [CacheKey: Data]? {
    guard let data = try? Data(contentsOf: NetworkRequestsCacher.fileWriteURL) else { return nil }
    return NSKeyedUnarchiver.unarchiveObject(with: data) as? [CacheKey: Data] ?? nil
  }

  static var fileWriteURL: URL {
    let manager = FileManager.default
    let url = manager.urls(for: .documentDirectory, in: .userDomainMask).first
    return (url!.appendingPathComponent("network-requests-cache"))
  }
}

class CacheKey: NSObject, NSCoding, NSCopying {

  override var hash: Int {
    return urlRequest.hashValue
  }

  let urlRequest: URLRequest
  init(urlRequest: URLRequest) {
    self.urlRequest = urlRequest
  }

  static func ==(lhs: CacheKey, rhs: CacheKey) -> Bool {
    guard lhs.urlRequest == rhs.urlRequest else { return false }
    return lhs.urlRequest.httpBody == rhs.urlRequest.httpBody
  }

  required init?(coder aDecoder: NSCoder){
    guard let urlRequest = aDecoder.decodeObject(forKey: "urlRequest") as? URLRequest else { return nil }
    self.urlRequest = urlRequest
  }

  override func copy() -> Any {
    return CacheKey(urlRequest: self.urlRequest)
  }

  func copy(with zone: NSZone? = nil) -> Any {
    return CacheKey(urlRequest: urlRequest)
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let rhs = (object as? CacheKey)?.urlRequest else { return false }
    let lhs = self.urlRequest
    guard lhs.url == rhs.url && lhs.allHTTPHeaderFields == rhs.allHTTPHeaderFields else { return false }
    return lhs.httpBody == rhs.httpBody
  }

  public func encode(with aCoder: NSCoder) {
    aCoder.encode(urlRequest, forKey:"urlRequest")
  }
}

#endif
