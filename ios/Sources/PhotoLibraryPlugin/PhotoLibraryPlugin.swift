import Capacitor
import Foundation
import Photos
import PhotosUI

@objc(PhotoLibraryPlugin)
public class PhotoLibraryPlugin: CAPPlugin, CAPBridgedPlugin {
    private let pluginVersion: String = "8.0.8"
    public let identifier = "PhotoLibraryPlugin"
    public let jsName = "PhotoLibrary"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "checkAuthorization", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestAuthorization", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getAlbums", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getLibrary", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPhotoUrl", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getThumbnailUrl", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pickMedia", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPluginVersion", returnType: CAPPluginReturnPromise)
    ]

    private var service = PhotoLibraryService()
    private var pendingPickCall: CAPPluginCall?
    private var pendingPickOptions: PhotoLibraryPickOptions?

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

    @objc public func pickMedia(_ call: CAPPluginCall) {
        guard #available(iOS 14, *) else {
            call.reject("pickMedia requires iOS 14 or newer")
            return
        }

        DispatchQueue.main.async {
            if self.pendingPickCall != nil {
                call.reject("Another pickMedia call is already in progress")
                return
            }

            do {
                let options = try PhotoLibraryPickOptions(from: call)
                var configuration = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
                configuration.selectionLimit = options.selectionLimit
                var filters: [PHPickerFilter] = []
                if options.includeImages {
                    filters.append(.images)
                }
                if options.includeVideos {
                    filters.append(.videos)
                }
                if filters.isEmpty {
                    filters = [.images]
                }
                configuration.filter = PHPickerFilter.any(of: filters)

                let picker = PHPickerViewController(configuration: configuration)
                picker.delegate = self

                guard let presenter = self.bridge?.viewController else {
                    call.reject("Unable to access view controller to present picker")
                    return
                }

                self.pendingPickCall = call
                self.pendingPickOptions = options
                presenter.present(picker, animated: true)
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }
}

@available(iOS 14, *)
extension PhotoLibraryPlugin: PHPickerViewControllerDelegate {
    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard let call = pendingPickCall else {
            return
        }

        let options = pendingPickOptions
        pendingPickCall = nil
        pendingPickOptions = nil

        guard let options = options else {
            call.resolve(["assets": []])
            return
        }

        service.processPickerResults(results, options: options) { [weak self] assets in
            guard let self = self else { return }
            let mapped = assets.map { $0.toDictionary(resolver: self.service.webPathResolver) }
            call.resolve(["assets": mapped])
        }
    }

    @objc func getPluginVersion(_ call: CAPPluginCall) {
        call.resolve(["version": self.pluginVersion])
    }

}
