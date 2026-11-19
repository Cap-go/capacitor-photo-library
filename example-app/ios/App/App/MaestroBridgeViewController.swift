import Capacitor
import Foundation

final class MaestroBridgeViewController: CAPBridgeViewController {
    private var shouldInjectMaestroFlag: Bool {
        ProcessInfo.processInfo.arguments.contains { argument in
            argument == "isE2E" || argument.hasPrefix("isE2E=")
        }
    }

    private var maestroFlowLaunchArgument: String? {
        let arguments = ProcessInfo.processInfo.arguments
        for (index, argument) in arguments.enumerated() {
            if argument == "capgoMaestroFlow", index + 1 < arguments.count {
                return arguments[index + 1]
            }
            if argument.hasPrefix("capgoMaestroFlow=") {
                let value = String(argument.dropFirst("capgoMaestroFlow=".count))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private func maestroHarnessJavaScript() -> String {
        var script = "window.__capgoMaestroIsE2E=true;"
        if let flowId = maestroFlowLaunchArgument?
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        {
            script += "window.__capgoMaestroFlow='\(flowId)';"
        }
        return script
    }

    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        #if DEBUG
        guard shouldInjectMaestroFlag else {
            return
        }
        bridge?.eval(js: maestroHarnessJavaScript())
        #endif
    }
}