import Foundation
import Capacitor

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(PhotoLibraryPlugin)
public class PhotoLibraryPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "PhotoLibraryPlugin"
    public let jsName = "PhotoLibrary"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "echo", returnType: CAPPluginReturnPromise)
    ]
    private let implementation = PhotoLibrary()

    @objc func echo(_ call: CAPPluginCall) {
        let value = call.getString("value") ?? ""
        call.resolve([
            "value": implementation.echo(value)
        ])
    }
}
