import Capacitor
import Foundation

final class MaestroBridgeViewController: CAPBridgeViewController {
    private var shouldInjectMaestroFlag: Bool {
        ProcessInfo.processInfo.arguments.contains { argument in
            argument == "isE2E" || argument.hasPrefix("isE2E=")
        }
    }

    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        #if DEBUG
        guard shouldInjectMaestroFlag else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.bridge?.eval(js: "window.__capgoMaestroIsE2E=true;")
        }
        #endif
    }
}