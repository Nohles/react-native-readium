import CryptoKit
import Foundation

/// Bounded on-disk cache of streamed comic page bytes, keyed by resource URL.
///
/// Pages of a streamed publication are downloaded ahead of display and land
/// here, so scrolling back or reopening a chapter reads from disk instead of
/// the network. It lives in the Caches directory, which the system may purge
/// under storage pressure; it is not an offline download. Least recently used
/// pages are evicted once the cache grows past `maxBytes`. Mirrors Android's
/// `ComicPageDiskCache.kt`.
final class ComicPageDiskCache {
  static let directoryName = "readium-comic-pages"
  static let defaultMaxBytes: Int64 = 512 * 1024 * 1024
  private static let trimTarget = 0.8

  /// Shared cache in the app's Caches directory; trimmed once per launch.
  static let shared: ComicPageDiskCache? = {
    guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
      return nil
    }
    let cache = ComicPageDiskCache(directory: caches.appendingPathComponent(directoryName, isDirectory: true))
    DispatchQueue.global(qos: .utility).async { cache.trim() }
    return cache
  }()

  private let directory: URL
  private let maxBytes: Int64
  private let fileManager = FileManager.default

  init(directory: URL, maxBytes: Int64 = ComicPageDiskCache.defaultMaxBytes) {
    self.directory = directory
    self.maxBytes = maxBytes
  }

  /// Cache key for a resource, or nil when it is not streamed over HTTP.
  static func key(for url: URL) -> String? {
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
    return url.absoluteString
  }

  func read(_ key: String) -> Data? {
    let file = fileURL(for: key)
    guard let data = try? Data(contentsOf: file) else { return nil }
    try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
    return data
  }

  func write(_ data: Data, for key: String) {
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      // `.atomic` writes to a temporary file and renames it into place.
      try data.write(to: fileURL(for: key), options: .atomic)
    } catch {
      // A cache write failure only costs a re-download.
    }
  }

  /// Evicts least recently used pages until the cache is under 80% of `maxBytes`.
  func trim() {
    let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
    guard let files = try? fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles]
    ) else { return }

    let entries: [(url: URL, size: Int64, modified: Date)] = files.compactMap { url in
      guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
        return nil
      }
      return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
    }
    var total = entries.reduce(Int64(0)) { $0 + $1.size }
    guard total > maxBytes else { return }
    let target = Int64(Double(maxBytes) * Self.trimTarget)
    for entry in entries.sorted(by: { $0.modified < $1.modified }) {
      guard total > target else { break }
      if (try? fileManager.removeItem(at: entry.url)) != nil {
        total -= entry.size
      }
    }
  }

  private func fileURL(for key: String) -> URL {
    let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(digest, isDirectory: false)
  }
}
