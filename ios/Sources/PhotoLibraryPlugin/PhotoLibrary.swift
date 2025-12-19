import Capacitor
import CryptoKit
import Foundation
import MobileCoreServices
import Photos
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import AVFoundation
import ImageIO

enum PhotoLibraryError: Error {
    case permissionDenied
    case assetNotFound
    case invalidOptions(String)

    var message: String {
        switch self {
        case .permissionDenied:
            return "Permission Denial: application is not allowed to access photo library."
        case .assetNotFound:
            return "Asset could not be found or no data was returned."
        case let .invalidOptions(reason):
            return "Invalid options: \(reason)"
        }
    }
}

enum PhotoLibraryDefaults {
    static let thumbnailWidth = 512
    static let thumbnailHeight = 384
    static let thumbnailQuality = 0.5
}

enum PhotoLibraryAuthorizationState: String {
    case authorized
    case limited
    case denied
    case notDetermined
}

struct PhotoLibraryFileResult {
    let url: URL
    let mimeType: String
    let size: Int64

    func toDictionary(resolver: PhotoLibraryService.WebPathResolver?) -> [String: Any] {
        let webPath = resolver?(url) ?? url.absoluteString
        return [
            "path": url.path,
            "webPath": webPath,
            "mimeType": mimeType,
            "size": size
        ]
    }
}

struct PhotoLibraryAssetResult {
    let id: String
    let fileName: String
    let type: String
    let width: Int
    let height: Int
    let duration: Double?
    let creationDate: String?
    let modificationDate: String?
    let latitude: Double?
    let longitude: Double?
    let mimeType: String
    let albumIds: [String]?
    let thumbnail: PhotoLibraryFileResult?
    let file: PhotoLibraryFileResult?

    func toDictionary(resolver: PhotoLibraryService.WebPathResolver?) -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "fileName": fileName,
            "type": type,
            "width": width,
            "height": height,
            "mimeType": mimeType
        ]

        if let duration = duration {
            dict["duration"] = duration
        }
        if let creationDate = creationDate {
            dict["creationDate"] = creationDate
        }
        if let modificationDate = modificationDate {
            dict["modificationDate"] = modificationDate
        }
        if let latitude = latitude {
            dict["latitude"] = latitude
        }
        if let longitude = longitude {
            dict["longitude"] = longitude
        }
        if let albumIds = albumIds {
            dict["albumIds"] = albumIds
        }
        if let thumbnail = thumbnail {
            dict["thumbnail"] = thumbnail.toDictionary(resolver: resolver)
        }
        if let file = file {
            dict["file"] = file.toDictionary(resolver: resolver)
        }

        return dict
    }
}

struct PhotoLibraryAlbumResult {
    let id: String
    let title: String
    let assetCount: Int

    func toDictionary(resolver _: PhotoLibraryService.WebPathResolver?) -> [String: Any] {
        return [
            "id": id,
            "title": title,
            "assetCount": assetCount
        ]
    }
}

struct PhotoLibraryFetchResult {
    let assets: [PhotoLibraryAssetResult]
    let totalCount: Int
    let hasMore: Bool
}

struct PhotoLibraryGetLibraryOptions {
    let offset: Int
    let limit: Int?
    let includeImages: Bool
    let includeVideos: Bool
    let includeAlbumData: Bool
    let includeCloudData: Bool
    let useOriginalFileNames: Bool
    let thumbnailWidth: Int
    let thumbnailHeight: Int
    let thumbnailQuality: Double
    let includeFullResolutionData: Bool

    init(from call: CAPPluginCall) throws {
        let offset = call.getInt("offset") ?? 0
        if offset < 0 {
            throw PhotoLibraryError.invalidOptions("offset must be greater than or equal to 0")
        }
        self.offset = offset

        if let limit = call.getInt("limit") {
            if limit < 0 {
                throw PhotoLibraryError.invalidOptions("limit must be greater than or equal to 0")
            }
            self.limit = limit == 0 ? nil : limit
        } else {
            self.limit = nil
        }

        var includeImages = call.getBool("includeImages") ?? true
        var includeVideos = call.getBool("includeVideos") ?? false

        if !includeImages && !includeVideos {
            includeImages = true
        }

        self.includeImages = includeImages
        self.includeVideos = includeVideos

        self.includeAlbumData = call.getBool("includeAlbumData") ?? false
        self.includeCloudData = call.getBool("includeCloudData") ?? true
        self.useOriginalFileNames = call.getBool("useOriginalFileNames") ?? false

        let width = call.getInt("thumbnailWidth") ?? PhotoLibraryDefaults.thumbnailWidth
        let height = call.getInt("thumbnailHeight") ?? PhotoLibraryDefaults.thumbnailHeight
        self.thumbnailWidth = max(0, width)
        self.thumbnailHeight = max(0, height)

        let quality = call.getDouble("thumbnailQuality") ?? PhotoLibraryDefaults.thumbnailQuality
        self.thumbnailQuality = max(0.0, min(1.0, quality))

        self.includeFullResolutionData = call.getBool("includeFullResolutionData") ?? false
    }
}

struct PhotoLibraryPickOptions {
    let selectionLimit: Int
    let includeImages: Bool
    let includeVideos: Bool
    let thumbnailWidth: Int
    let thumbnailHeight: Int
    let thumbnailQuality: Double

    init(from call: CAPPluginCall) throws {
        let selectionLimit = call.getInt("selectionLimit") ?? 1
        if selectionLimit < 0 {
            throw PhotoLibraryError.invalidOptions("selectionLimit must be greater than or equal to 0")
        }
        self.selectionLimit = selectionLimit

        var includeImages = call.getBool("includeImages") ?? true
        var includeVideos = call.getBool("includeVideos") ?? false

        if !includeImages && !includeVideos {
            includeImages = true
        }

        self.includeImages = includeImages
        self.includeVideos = includeVideos

        let width = call.getInt("thumbnailWidth") ?? 256
        let height = call.getInt("thumbnailHeight") ?? 256
        self.thumbnailWidth = max(0, width)
        self.thumbnailHeight = max(0, height)

        let quality = call.getDouble("thumbnailQuality") ?? 0.7
        self.thumbnailQuality = max(0.0, min(1.0, quality))
    }
}

final class PhotoLibraryService {
    typealias WebPathResolver = (URL) -> String?

    private let queue = DispatchQueue(label: "capgo.photolibrary", qos: .userInitiated)
    private let fileManager = FileManager.default
    private let dateFormatter: ISO8601DateFormatter
    private let imageManager = PHCachingImageManager()
    private let cacheRoot: URL
    private let thumbnailDirectory: URL
    private let fileDirectory: URL
    private let albumCollectionTypes: [PHAssetCollectionType] = [.album, .smartAlbum]
    private let mimeTypes: [String: String] = [
        "flv": "video/x-flv",
        "mp4": "video/mp4",
        "m3u8": "application/x-mpegURL",
        "ts": "video/MP2T",
        "3gp": "video/3gpp",
        "mov": "video/quicktime",
        "avi": "video/x-msvideo",
        "wmv": "video/x-ms-wmv",
        "gif": "image/gif",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "png": "image/png",
        "tiff": "image/tiff",
        "tif": "image/tiff",
        "heic": "image/heic",
        "heif": "image/heif"
    ]

    private struct PickedItem {
        let fileURL: URL
        let mimeType: String
        let type: String
    }

    var webPathResolver: WebPathResolver?
    private var pickedItems: [String: PickedItem] = [:]

    init(webPathResolver: WebPathResolver? = nil) {
        self.webPathResolver = webPathResolver
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        cacheRoot = caches.appendingPathComponent("CapPhotoLibrary", isDirectory: true)
        thumbnailDirectory = cacheRoot.appendingPathComponent("thumbnails", isDirectory: true)
        fileDirectory = cacheRoot.appendingPathComponent("files", isDirectory: true)
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    var isAccessGranted: Bool {
        switch currentAuthorizationState() {
        case .authorized, .limited:
            return true
        case .denied, .notDetermined:
            return false
        }
    }

    func prepareCacheDirectories() {
        createDirectoryIfNeeded(at: cacheRoot)
        createDirectoryIfNeeded(at: thumbnailDirectory)
        createDirectoryIfNeeded(at: fileDirectory)
    }

    private func createDirectoryIfNeeded(at url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }

    func currentAuthorizationState() -> PhotoLibraryAuthorizationState {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return authorizationState(from: status)
    }

    func requestAuthorization(completion: @escaping (PhotoLibraryAuthorizationState) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                completion(self.authorizationState(from: status))
            }
        }
    }

    func fetchAlbums(completion: @escaping ([PhotoLibraryAlbumResult]) -> Void) {
        queue.async {
            var result: [PhotoLibraryAlbumResult] = []
            for type in self.albumCollectionTypes {
                let collections = PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: nil)
                collections.enumerateObjects { collection, _, _ in
                    let count = PHAsset.fetchAssets(in: collection, options: nil).count
                    let album = PhotoLibraryAlbumResult(
                        id: collection.localIdentifier,
                        title: collection.localizedTitle ?? "",
                        assetCount: count
                    )
                    result.append(album)
                }
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func fetchLibrary(options: PhotoLibraryGetLibraryOptions, completion: @escaping (PhotoLibraryFetchResult) -> Void) {
        queue.async {
            let fetchOptions = self.buildFetchOptions(from: options)
            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
            let totalCount = fetchResult.count

            if totalCount == 0 {
                let empty = PhotoLibraryFetchResult(assets: [], totalCount: 0, hasMore: false)
                DispatchQueue.main.async {
                    completion(empty)
                }
                return
            }

            let offset = min(max(options.offset, 0), totalCount)
            let upperBound = options.limit != nil ? min(totalCount, offset + (options.limit ?? 0)) : totalCount

            if offset >= upperBound {
                let empty = PhotoLibraryFetchResult(assets: [], totalCount: totalCount, hasMore: false)
                DispatchQueue.main.async {
                    completion(empty)
                }
                return
            }

            var assets: [PhotoLibraryAssetResult] = []
            assets.reserveCapacity(max(upperBound - offset, 0))

            for index in stride(from: offset, to: upperBound, by: 1) {
                let asset = fetchResult.object(at: index)
                if let item = self.assetResult(for: asset, options: options) {
                    assets.append(item)
                }
            }

            let hasMore = upperBound < totalCount
            let result = PhotoLibraryFetchResult(assets: assets, totalCount: totalCount, hasMore: hasMore)

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    @available(iOS 14, *)
    func processPickerResults(_ results: [PHPickerResult], options: PhotoLibraryPickOptions, completion: @escaping ([PhotoLibraryAssetResult]) -> Void) {
        queue.async {
            guard !results.isEmpty else {
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }

            let group = DispatchGroup()
            var assets: [PhotoLibraryAssetResult] = []
            let lock = NSLock()

            for result in results {
                group.enter()
                self.assetFromPickerResult(result, options: options) { asset in
                    if let asset = asset {
                        lock.lock()
                        assets.append(asset)
                        lock.unlock()
                    }
                    group.leave()
                }
            }

            group.notify(queue: self.queue) {
                DispatchQueue.main.async {
                    completion(assets)
                }
            }
        }
    }

    func fetchFullResolutionFile(for assetId: String, allowNetworkAccess: Bool, completion: @escaping (PhotoLibraryFileResult?) -> Void) {
        queue.async {
            if let picked = self.pickedItems[assetId] {
                let fileResult = PhotoLibraryFileResult(url: picked.fileURL, mimeType: picked.mimeType, size: self.fileSize(at: picked.fileURL))
                DispatchQueue.main.async {
                    completion(fileResult)
                }
                return
            }

            guard let asset = self.fetchAsset(with: assetId) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            let file = self.fullResolutionFile(for: asset, allowNetworkAccess: allowNetworkAccess)
            DispatchQueue.main.async {
                completion(file)
            }
        }
    }

    func fetchThumbnailFile(for assetId: String, width: Int, height: Int, quality: Double, allowNetworkAccess: Bool, completion: @escaping (PhotoLibraryFileResult?) -> Void) {
        queue.async {
            if let picked = self.pickedItems[assetId] {
                let file = self.thumbnailForPickedItem(identifier: assetId, item: picked, width: width, height: height, quality: quality)
                DispatchQueue.main.async {
                    completion(file)
                }
                return
            }

            guard let asset = self.fetchAsset(with: assetId) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            let file = self.thumbnailFile(for: asset, width: width, height: height, quality: quality, allowNetworkAccess: allowNetworkAccess)
            DispatchQueue.main.async {
                completion(file)
            }
        }
    }

    private func buildFetchOptions(from options: PhotoLibraryGetLibraryOptions) -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        if options.includeImages && options.includeVideos {
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d || mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        } else if options.includeImages {
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        } else if options.includeVideos {
            fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        }

        if !options.includeCloudData {
            if #available(iOS 9.0, *) {
                fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeiTunesSynced]
            }
        }

        return fetchOptions
    }

    private func assetResult(for asset: PHAsset, options: PhotoLibraryGetLibraryOptions) -> PhotoLibraryAssetResult? {
        let type: String
        switch asset.mediaType {
        case .image:
            type = "image"
        case .video:
            type = "video"
        default:
            return nil
        }

        let fileName: String
        if options.useOriginalFileNames, let original = asset.originalFileName {
            fileName = original
        } else if let name = asset.fileName {
            fileName = name
        } else {
            fileName = "asset"
        }

        let resource = preferredResource(for: asset)
        let mimeType = mimeType(for: resource, fallbackName: fileName)

        let creationDate = asset.creationDate != nil ? dateFormatter.string(from: asset.creationDate!) : nil
        let modificationDate = asset.modificationDate != nil ? dateFormatter.string(from: asset.modificationDate!) : nil
        let latitude = asset.location?.coordinate.latitude
        let longitude = asset.location?.coordinate.longitude
        let duration = asset.mediaType == .video ? asset.duration : nil

        var albumIds: [String]?
        if options.includeAlbumData {
            albumIds = albumIdentifiers(for: asset)
        }

        var thumbnail: PhotoLibraryFileResult?
        if options.thumbnailWidth > 0 && options.thumbnailHeight > 0 {
            thumbnail = thumbnailFile(for: asset,
                                      width: options.thumbnailWidth,
                                      height: options.thumbnailHeight,
                                      quality: options.thumbnailQuality,
                                      allowNetworkAccess: options.includeCloudData)
        }

        let file: PhotoLibraryFileResult?
        if options.includeFullResolutionData {
            file = fullResolutionFile(for: asset, allowNetworkAccess: options.includeCloudData)
        } else {
            file = nil
        }

        return PhotoLibraryAssetResult(
            id: asset.localIdentifier,
            fileName: fileName,
            type: type,
            width: asset.pixelWidth,
            height: asset.pixelHeight,
            duration: duration,
            creationDate: creationDate,
            modificationDate: modificationDate,
            latitude: latitude,
            longitude: longitude,
            mimeType: mimeType,
            albumIds: albumIds,
            thumbnail: thumbnail,
            file: file
        )
    }

    @available(iOS 14, *)
    private func assetFromPickerResult(_ result: PHPickerResult, options: PhotoLibraryPickOptions, completion: @escaping (PhotoLibraryAssetResult?) -> Void) {
        let provider = result.itemProvider
        let identifier = result.assetIdentifier ?? "picked-\(UUID().uuidString)"

        if options.includeImages && provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else {
                    completion(nil)
                    return
                }
                self.queue.async {
                    let asset = self.createAssetFromPickedImage(image: image, identifier: identifier, suggestedName: provider.suggestedName, options: options)
                    completion(asset)
                }
            }
            return
        }

        if options.includeVideos && provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let url = url else {
                    completion(nil)
                    return
                }
                self.queue.async {
                    let asset = self.createAssetFromPickedVideo(tempURL: url, identifier: identifier, suggestedName: provider.suggestedName, options: options)
                    completion(asset)
                }
            }
            return
        }

        completion(nil)
    }

    @available(iOS 14, *)
    private func createAssetFromPickedImage(image: UIImage, identifier: String, suggestedName: String?, options: PhotoLibraryPickOptions) -> PhotoLibraryAssetResult? {
        let baseName = (suggestedName?.isEmpty ?? true) ? "\(identifier).jpg" : suggestedName!
        let ext = (baseName as NSString).pathExtension.isEmpty ? "jpg" : (baseName as NSString).pathExtension
        let hashed = hashedIdentifier(identifier)
        let fileURL = fileDirectory.appendingPathComponent("\(hashed).\(ext)")

        guard let data = image.jpegData(compressionQuality: 1.0) else {
            return nil
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            CAPLog.print("PhotoLibrary: failed to persist picked image: \(error.localizedDescription)")
            return nil
        }

        let mimeType = mimeType(for: nil, fallbackName: fileURL.lastPathComponent)
        let fileResult = PhotoLibraryFileResult(url: fileURL, mimeType: mimeType, size: fileSize(at: fileURL))

        var thumbnail: PhotoLibraryFileResult?
        if options.thumbnailWidth > 0 && options.thumbnailHeight > 0 {
            thumbnail = createThumbnail(from: image, identifier: identifier, width: options.thumbnailWidth, height: options.thumbnailHeight, quality: options.thumbnailQuality)
        }

        pickedItems[identifier] = PickedItem(fileURL: fileURL, mimeType: mimeType, type: "image")

        let pixelWidth = Int(image.size.width * image.scale)
        let pixelHeight = Int(image.size.height * image.scale)

        return PhotoLibraryAssetResult(
            id: identifier,
            fileName: baseName,
            type: "image",
            width: pixelWidth,
            height: pixelHeight,
            duration: nil,
            creationDate: nil,
            modificationDate: nil,
            latitude: nil,
            longitude: nil,
            mimeType: mimeType,
            albumIds: nil,
            thumbnail: thumbnail,
            file: fileResult
        )
    }

    @available(iOS 14, *)
    private func createAssetFromPickedVideo(tempURL: URL, identifier: String, suggestedName: String?, options: PhotoLibraryPickOptions) -> PhotoLibraryAssetResult? {
        let baseName = (suggestedName?.isEmpty ?? true) ? tempURL.lastPathComponent : suggestedName!
        let ext = (baseName as NSString).pathExtension.isEmpty ? "mov" : (baseName as NSString).pathExtension
        let hashed = hashedIdentifier(identifier)
        let fileURL = fileDirectory.appendingPathComponent("\(hashed).\(ext)")

        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            try fileManager.copyItem(at: tempURL, to: fileURL)
        } catch {
            CAPLog.print("PhotoLibrary: failed to persist picked video: \(error.localizedDescription)")
            return nil
        }

        let asset = AVAsset(url: fileURL)
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        var width = 0
        var height = 0
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            width = Int(abs(size.width))
            height = Int(abs(size.height))
        }

        let mimeType = mimeType(for: nil, fallbackName: fileURL.lastPathComponent)
        let fileResult = PhotoLibraryFileResult(url: fileURL, mimeType: mimeType, size: fileSize(at: fileURL))

        var thumbnail: PhotoLibraryFileResult?
        if options.thumbnailWidth > 0 && options.thumbnailHeight > 0 {
            thumbnail = createThumbnail(from: asset, identifier: identifier, width: options.thumbnailWidth, height: options.thumbnailHeight, quality: options.thumbnailQuality)
        }

        pickedItems[identifier] = PickedItem(fileURL: fileURL, mimeType: mimeType, type: "video")

        return PhotoLibraryAssetResult(
            id: identifier,
            fileName: baseName,
            type: "video",
            width: width,
            height: height,
            duration: durationSeconds.isFinite ? durationSeconds : nil,
            creationDate: nil,
            modificationDate: nil,
            latitude: nil,
            longitude: nil,
            mimeType: mimeType,
            albumIds: nil,
            thumbnail: thumbnail,
            file: fileResult
        )
    }

    private func thumbnailURL(for identifier: String, width: Int, height: Int, quality: Double) -> URL {
        let fileName = String(format: "%@_%dx%d_q%.0f.jpg", hashedIdentifier(identifier), width, height, quality * 100)
        return thumbnailDirectory.appendingPathComponent(fileName)
    }

    private func createThumbnail(from image: UIImage, identifier: String, width: Int, height: Int, quality: Double) -> PhotoLibraryFileResult? {
        let targetSize = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let scaledImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let data = scaledImage.jpegData(compressionQuality: CGFloat(quality)) else {
            return nil
        }

        let url = thumbnailURL(for: identifier, width: width, height: height, quality: quality)

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            CAPLog.print("PhotoLibrary: failed to write picked thumbnail: \(error.localizedDescription)")
            return nil
        }

        return PhotoLibraryFileResult(url: url, mimeType: "image/jpeg", size: fileSize(at: url))
    }

    private func createThumbnail(from asset: AVAsset, identifier: String, width: Int, height: Int, quality: Double) -> PhotoLibraryFileResult? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: width, height: height)

        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
            return nil
        }

        let image = UIImage(cgImage: cgImage)
        return createThumbnail(from: image, identifier: identifier, width: width, height: height, quality: quality)
    }

    private func thumbnailForPickedItem(identifier: String, item: PickedItem, width: Int, height: Int, quality: Double) -> PhotoLibraryFileResult? {
        guard width > 0, height > 0 else {
            return nil
        }

        let url = thumbnailURL(for: identifier, width: width, height: height, quality: quality)
        if fileManager.fileExists(atPath: url.path) {
            return PhotoLibraryFileResult(url: url, mimeType: "image/jpeg", size: fileSize(at: url))
        }

        switch item.type {
        case "image":
            guard let image = UIImage(contentsOfFile: item.fileURL.path) else {
                return nil
            }
            return createThumbnail(from: image, identifier: identifier, width: width, height: height, quality: quality)
        case "video":
            let asset = AVAsset(url: item.fileURL)
            return createThumbnail(from: asset, identifier: identifier, width: width, height: height, quality: quality)
        default:
            return nil
        }
    }

    private func fetchAsset(with id: String) -> PHAsset? {
        let results = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        return results.firstObject
    }

    private func fullResolutionFile(for asset: PHAsset, allowNetworkAccess: Bool) -> PhotoLibraryFileResult? {
        guard let resource = preferredResource(for: asset) else {
            return nil
        }

        let fileExtension = (resource.originalFilename as NSString?)?.pathExtension
        let hashed = hashedIdentifier(asset.localIdentifier)
        let ext = (fileExtension?.isEmpty ?? true) ? suggestedExtension(for: resource) : fileExtension!
        let url = fileDirectory.appendingPathComponent("\(hashed).\(ext)")

        if !fileManager.fileExists(atPath: url.path) {
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = allowNetworkAccess
            let semaphore = DispatchSemaphore(value: 0)
            var writeError: Error?

            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                writeError = error
                semaphore.signal()
            }

            semaphore.wait()

            if let error = writeError {
                CAPLog.print("PhotoLibrary: failed to export asset \(asset.localIdentifier): \(error.localizedDescription)")
                try? fileManager.removeItem(at: url)
                return nil
            }
        }

        let size = fileSize(at: url)
        let mimeType = mimeType(for: resource, fallbackName: url.lastPathComponent)
        return PhotoLibraryFileResult(url: url, mimeType: mimeType, size: size)
    }

    private func thumbnailFile(for asset: PHAsset, width: Int, height: Int, quality: Double, allowNetworkAccess: Bool) -> PhotoLibraryFileResult? {
        let fileName = String(format: "%@_%dx%d_q%.0f.jpg", hashedIdentifier(asset.localIdentifier), width, height, quality * 100)
        let url = thumbnailDirectory.appendingPathComponent(fileName)

        if !fileManager.fileExists(atPath: url.path) {
            let options = PHImageRequestOptions()
            options.isSynchronous = true
            options.resizeMode = .exact
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = allowNetworkAccess

            var imageData: Data?
            imageManager.requestImage(for: asset,
                                      targetSize: CGSize(width: width, height: height),
                                      contentMode: .aspectFill,
                                      options: options) { image, _ in
                if let image = image {
                    imageData = image.jpegData(compressionQuality: CGFloat(quality))
                }
            }

            guard let data = imageData else {
                return nil
            }

            do {
                try data.write(to: url, options: .atomic)
            } catch {
                CAPLog.print("PhotoLibrary: failed to write thumbnail for \(asset.localIdentifier): \(error.localizedDescription)")
                return nil
            }
        }

        return PhotoLibraryFileResult(url: url, mimeType: "image/jpeg", size: fileSize(at: url))
    }

    private func authorizationState(from status: PHAuthorizationStatus) -> PhotoLibraryAuthorizationState {
        switch status {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        default:
            if #available(iOS 14.0, *), status == .limited {
                return .limited
            }
            return .denied
        }
    }

    private func preferredResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)

        switch asset.mediaType {
        case .image:
            if let resource = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto || $0.type == .alternatePhoto }) {
                return resource
            }
        case .video:
            if let resource = resources.first(where: { $0.type == .video || $0.type == .fullSizeVideo }) {
                return resource
            }
        default:
            break
        }

        return resources.first
    }

    private func mimeType(for resource: PHAssetResource?, fallbackName: String) -> String {
        if let uniformTypeIdentifier = resource?.uniformTypeIdentifier {
            if let type = UTType(uniformTypeIdentifier), let mime = type.preferredMIMEType {
                return mime
            }
        }

        let fallbackFilename = resource?.originalFilename ?? fallbackName
        let ext = (fallbackFilename as NSString).pathExtension.lowercased()
        if let mime = mimeTypes[ext] {
            return mime
        }
        return "application/octet-stream"
    }

    private func suggestedExtension(for resource: PHAssetResource?) -> String {
        if let fileName = resource?.originalFilename, !fileName.isEmpty {
            let ext = (fileName as NSString).pathExtension
            if !ext.isEmpty {
                return ext
            }
        }

        if let uti = resource?.uniformTypeIdentifier {
            if let type = UTType(uti), let preferredExt = type.preferredFilenameExtension {
                return preferredExt
            }
        }

        return "dat"
    }

    private func albumIdentifiers(for asset: PHAsset) -> [String] {
        var identifiers: [String] = []
        for type in albumCollectionTypes {
            let collections = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: type, options: nil)
            collections.enumerateObjects { collection, _, _ in
                identifiers.append(collection.localIdentifier)
            }
        }
        return identifiers
    }

    private func hashedIdentifier(_ identifier: String) -> String {
        let digest = SHA256.hash(data: Data(identifier.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fileSize(at url: URL) -> Int64 {
        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attributes[FileAttributeKey.size] as? NSNumber {
            return size.int64Value
        }
        return -1
    }
}

private extension CAPPluginCall {
    func getDouble(_ key: String) -> Double? {
        guard let value = options?[key] else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }

        if let string = value as? String {
            return Double(string)
        }

        return nil
    }
}

private extension PHAsset {
    var originalFileName: String? {
        if #available(iOS 9.0, *) {
            let resources = PHAssetResource.assetResources(for: self)
            return resources.first?.originalFilename
        }
        return nil
    }

    var fileName: String? {
        return value(forKey: "filename") as? String
    }
}
