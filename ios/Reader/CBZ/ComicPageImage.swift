import ImageIO
import UIKit

/// ImageIO helpers for comic pages: read a page's size from its header, and
/// decode it downsampled to the size it is drawn at, off the main thread.
enum ComicPageImage {
  /// Pixel size from the image header, without decoding pixels.
  static func pixelSize(of data: Data) -> CGSize? {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard
      let source = CGImageSourceCreateWithData(data as CFData, options),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
      width > 0, height > 0
    else { return nil }
    // EXIF orientations 5-8 rotate the image a quarter turn.
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
  }

  /// Fully decoded image no larger than `maxPixelSize` on its longer side.
  ///
  /// `UIImage(data:)` defers decoding until the first draw, which happens on
  /// the main thread mid-scroll; decoding here, with the cache forced, keeps
  /// that work off the main thread and bounds memory to the display size.
  static func decode(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
    let options = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize.rounded(.up))),
    ] as [CFString: Any] as CFDictionary
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
    return UIImage(cgImage: image)
  }
}
