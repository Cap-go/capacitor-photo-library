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
                if !value.isEmpty {
                    return value
                }
            }
            if argument.hasPrefix("isE2E=") {
                let value = String(argument.dropFirst("isE2E=".count))
                if !value.isEmpty && value != "true" && value != "1" {
                    return value
                }
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
        let script = maestroHarnessJavaScript()
        bridge?.eval(js: script)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.bridge?.eval(js: script)
        }
        #endif
    }
}