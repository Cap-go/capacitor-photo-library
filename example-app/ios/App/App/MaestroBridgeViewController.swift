import Capacitor
import Foundation

final class MaestroBridgeViewController: CAPBridgeViewController {
    private var shouldInjectMaestroFlag: Bool {
        if let envFlow = ProcessInfo.processInfo.environment["CAPGO_MAESTRO_FLOW"], !envFlow.isEmpty {
            return true
        }
        return ProcessInfo.processInfo.arguments.contains { argument in
            argument == "isE2E" || argument.hasPrefix("isE2E=")
        }
    }

    private var maestroFlowLaunchArgument: String? {
        if let envFlow = ProcessInfo.processInfo.environment["CAPGO_MAESTRO_FLOW"],
           !envFlow.isEmpty
        {
            return envFlow
        }
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
            if argument == "isE2E", index + 1 < arguments.count {
                let value = arguments[index + 1]
                if !value.isEmpty && value != "true" && value != "1" && !value.hasPrefix("-") {
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

    private func scheduleMaestroAutoRunIfNeeded() {
        guard let flowId = maestroFlowLaunchArgument else {
            return
        }
        let escapedFlow = flowId
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (function capgoTryAutoRunFlow(attempts) {
          if (typeof globalThis.__capgoMaestroRunFlow === 'function') {
            globalThis.__capgoMaestroRunFlow('\(escapedFlow)');
            return;
          }
          if (attempts < 120) {
            setTimeout(function(){ capgoTryAutoRunFlow(attempts + 1); }, 250);
          }
        })(0);
        """
        bridge?.eval(js: script)
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
        scheduleMaestroAutoRunIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.bridge?.eval(js: script)
            self?.scheduleMaestroAutoRunIfNeeded()
        }
        #endif
    }
}