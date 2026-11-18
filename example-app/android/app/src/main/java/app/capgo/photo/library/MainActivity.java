package app.capgo.photo.library;

import android.content.Intent;
import android.os.Bundle;
import com.getcapacitor.Bridge;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    private String pendingAutoFlow;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        captureAutoFlow(getIntent());
        super.onCreate(savedInstanceState);
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        captureAutoFlow(intent);
    }

    @Override
    public void onResume() {
        super.onResume();
        injectAutoFlow();
    }

    private void captureAutoFlow(Intent intent) {
        if (intent == null || intent.getExtras() == null) {
            return;
        }
        String flow = intent.getExtras().getString("capgoMaestroFlow");
        if (flow != null && !flow.isEmpty()) {
            pendingAutoFlow = flow;
        }
    }

    private void injectAutoFlow() {
        if (pendingAutoFlow == null) {
            return;
        }
        Bridge bridge = getBridge();
        if (bridge == null || bridge.getWebView() == null) {
            return;
        }
        final String safeFlow = pendingAutoFlow.replace("'", "\\'");
        pendingAutoFlow = null;
        bridge.getWebView().post(() -> bridge.eval("window.__capgoMaestroAutoFlow='" + safeFlow + "';", null));
    }
}