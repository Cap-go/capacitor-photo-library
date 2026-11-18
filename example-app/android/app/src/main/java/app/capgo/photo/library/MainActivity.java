package app.capgo.photo.library;

import android.content.Intent;
import android.os.Bundle;
import com.getcapacitor.BridgeActivity;
import org.json.JSONObject;

public class MainActivity extends BridgeActivity {
    private String pendingMaestroFlow;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        captureMaestroFlow(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        captureMaestroFlow(intent);
        injectMaestroFlow();
    }

    @Override
    public void onResume() {
        super.onResume();
        injectMaestroFlow();
    }

    private void captureMaestroFlow(Intent intent) {
        if (intent == null) {
            return;
        }
        String flow = intent.getStringExtra("capgoMaestroFlow");
        if (flow != null && !flow.isEmpty()) {
            pendingMaestroFlow = flow;
        }
    }

    private void injectMaestroFlow() {
        if (pendingMaestroFlow == null || getBridge() == null) {
            return;
        }
        final String js =
            "window.__capgoMaestroAutoFlow="
                + JSONObject.quote(pendingMaestroFlow)
                + ";window.dispatchEvent(new CustomEvent('capgoMaestroAutoFlow'));";
        pendingMaestroFlow = null;
        getBridge()
            .getWebView()
            .post(() -> getBridge().getWebView().evaluateJavascript(js, null));
    }
}