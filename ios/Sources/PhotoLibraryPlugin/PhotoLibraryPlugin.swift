import Capacitor
import Foundation
import Photos

@objc(PhotoLibraryPlugin)
public class PhotoLibraryPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "PhotoLibraryPlugin"
    public let jsName = "PhotoLibrary"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "checkAuthorization", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestAuthorization", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getAlbums", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getLibrary", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPhotoUrl", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getThumbnailUrl", returnType: CAPPluginReturnPromise)
    ]

    private var service = PhotoLibraryService()

    override public func load() {
        super.load()
        service.webPathResolver = { [weak self] localURL in
            guard let portable = self?.bridge?.portablePath(fromLocalURL: localURL) else {
                return nil
            }
            return portable.absoluteString
        }
        service.prepareCacheDirectories()
    }

    @objc public func checkAuthorization(_ call: CAPPluginCall) {
        let state = service.currentAuthorizationState()
        call.resolve(["state": state.rawValue])
    }

    @objc public func requestAuthorization(_ call: CAPPluginCall) {
        service.requestAuthorization { state in
            call.resolve(["state": state.rawValue])
        }
    }

    @objc public func getAlbums(_ call: CAPPluginCall) {
        guard service.isAccessGranted else {
            call.reject(PhotoLibraryError.permissionDenied.message)
            return
        }

        service.fetchAlbums { [weak self] albums in
            guard let self = self else { return }
            let data = albums.map { $0.toDictionary(resolver: self.service.webPathResolver) }
            call.resolve(["albums": data])
        }
    }

    @objc public func getLibrary(_ call: CAPPluginCall) {
        guard service.isAccessGranted else {
            call.reject(PhotoLibraryError.permissionDenied.message)
            return
        }

        do {
            let options = try PhotoLibraryGetLibraryOptions(from: call)
            service.fetchLibrary(options: options) { [weak self] result in
                guard let self = self else { return }
                let assets = result.assets.map { $0.toDictionary(resolver: self.service.webPathResolver) }
                call.resolve([
                    "assets": assets,
                    "totalCount": result.totalCount,
                    "hasMore": result.hasMore
                ])
            }
        } catch {
            call.reject(error.localizedDescription)
        }
    }

    @objc public func getPhotoUrl(_ call: CAPPluginCall) {
        guard service.isAccessGranted else {
            call.reject(PhotoLibraryError.permissionDenied.message)
            return
        }

        guard let id = call.getString("id"), !id.isEmpty else {
            call.reject("Parameter 'id' is required")
            return
        }

        service.fetchFullResolutionFile(for: id, allowNetworkAccess: true) { [weak self] file in
            guard let self = self else { return }
            guard let file = file else {
                call.reject(PhotoLibraryError.assetNotFound.message)
                return
            }
            call.resolve(file.toDictionary(resolver: self.service.webPathResolver))
        }
    }

    @objc public func getThumbnailUrl(_ call: CAPPluginCall) {
        guard service.isAccessGranted else {
            call.reject(PhotoLibraryError.permissionDenied.message)
            return
        }

        guard let id = call.getString("id"), !id.isEmpty else {
            call.reject("Parameter 'id' is required")
            return
        }

        let width = call.getInt("width") ?? PhotoLibraryDefaults.thumbnailWidth
        let height = call.getInt("height") ?? PhotoLibraryDefaults.thumbnailHeight
        let quality = call.getDouble("quality") ?? PhotoLibraryDefaults.thumbnailQuality

        service.fetchThumbnailFile(for: id, width: width, height: height, quality: quality, allowNetworkAccess: true) { [weak self] file in
            guard let self = self else { return }
            guard let file = file else {
                call.reject(PhotoLibraryError.assetNotFound.message)
                return
            }
            call.resolve(file.toDictionary(resolver: self.service.webPathResolver))
        }
    }
}
