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
        final String flow = pendingMaestroFlow;
        final String js =
            "(function(){var flow="
                + JSONObject.quote(flow)
                + ";var ticks=0;var timer=setInterval(function(){ticks+=1;"
                + "var ready=document.getElementById('harness-ready');"
                + "if(!ready||ready.textContent.indexOf('Harness: ready')<0){"
                + "if(ticks>=120){clearInterval(timer);}return;}"
                + "clearInterval(timer);window.__capgoMaestroAutoFlow=flow;"
                + "window.dispatchEvent(new CustomEvent('capgoMaestroAutoFlow'));},250);})();";
        getBridge()
            .getWebView()
            .post(
                () ->
                    getBridge()
                        .getWebView()
                        .evaluateJavascript(
                            js,
                            value -> {
                                if (flow.equals(pendingMaestroFlow)) {
                                    pendingMaestroFlow = null;
                                }
                            }
                        )
            );
    }
}