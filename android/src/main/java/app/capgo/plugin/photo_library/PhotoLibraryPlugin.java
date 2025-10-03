package app.capgo.plugin.photo_library;

import android.Manifest;
import android.os.Build;
import androidx.annotation.NonNull;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@CapacitorPlugin(
    name = "PhotoLibrary",
    permissions = {
        @Permission(
            strings = { Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO },
            alias = PhotoLibraryPlugin.PERMISSION_MEDIA
        ),
        @Permission(strings = { Manifest.permission.READ_EXTERNAL_STORAGE }, alias = PhotoLibraryPlugin.PERMISSION_MEDIA_LEGACY)
    }
)
public class PhotoLibraryPlugin extends Plugin {

    static final String PERMISSION_MEDIA = "media";
    static final String PERMISSION_MEDIA_LEGACY = "media_legacy";

    private static final String STATE_AUTHORIZED = "authorized";
    private static final String STATE_DENIED = "denied";

    private final ExecutorService executor = Executors.newFixedThreadPool(2);
    private PhotoLibraryService service;

    @Override
    public void load() {
        super.load();
        service = new PhotoLibraryService(getContext(), getBridge());
        service.prepareCacheDirectories();
    }

    @Override
    protected void handleOnDestroy() {
        super.handleOnDestroy();
        executor.shutdown();
        service = null;
    }

    @PluginMethod
    public void checkAuthorization(PluginCall call) {
        call.resolve(statusObject(currentAuthorizationState()));
    }

    @PluginMethod
    public void requestAuthorization(PluginCall call) {
        String alias = permissionAlias();
        if (hasPermission(alias)) {
            call.resolve(statusObject(STATE_AUTHORIZED));
            return;
        }

        bridge.saveCall(call);
        requestPermissionForAlias(alias, call, "permissionCallback");
    }

    @PermissionCallback
    private void permissionCallback(PluginCall call) {
        String state = hasMediaPermissions() ? STATE_AUTHORIZED : STATE_DENIED;
        call.resolve(statusObject(state));
    }

    @PluginMethod
    public void getAlbums(PluginCall call) {
        if (!hasMediaPermissions()) {
            call.reject(PhotoLibraryService.PERMISSION_ERROR);
            return;
        }

        executor.execute(() -> {
            try {
                JSArray albums = service.fetchAlbums();
                JSObject result = new JSObject();
                result.put("albums", albums);
                call.resolve(result);
            } catch (Exception ex) {
                call.reject(ex.getMessage(), ex);
            }
        });
    }

    @PluginMethod
    public void getLibrary(PluginCall call) {
        if (!hasMediaPermissions()) {
            call.reject(PhotoLibraryService.PERMISSION_ERROR);
            return;
        }

        GetLibraryOptions options;
        try {
            options = GetLibraryOptions.fromCall(call);
        } catch (IllegalArgumentException ex) {
            call.reject(ex.getMessage());
            return;
        }

        executor.execute(() -> {
            try {
                PhotoLibraryFetchResult result = service.fetchLibrary(options);
                JSObject payload = new JSObject();
                payload.put("assets", result.assets);
                payload.put("totalCount", result.totalCount);
                payload.put("hasMore", result.hasMore);
                call.resolve(payload);
            } catch (Exception ex) {
                call.reject(ex.getMessage(), ex);
            }
        });
    }

    @PluginMethod
    public void getPhotoUrl(PluginCall call) {
        if (!hasMediaPermissions()) {
            call.reject(PhotoLibraryService.PERMISSION_ERROR);
            return;
        }

        String id = call.getString("id");
        if (id == null || id.isEmpty()) {
            call.reject("Parameter 'id' is required");
            return;
        }

        executor.execute(() -> {
            try {
                JSObject file = service.getFullResolutionFile(id);
                if (file == null) {
                    call.reject(PhotoLibraryService.ASSET_NOT_FOUND);
                    return;
                }
                call.resolve(file);
            } catch (Exception ex) {
                call.reject(ex.getMessage(), ex);
            }
        });
    }

    @PluginMethod
    public void getThumbnailUrl(PluginCall call) {
        if (!hasMediaPermissions()) {
            call.reject(PhotoLibraryService.PERMISSION_ERROR);
            return;
        }

        String id = call.getString("id");
        if (id == null || id.isEmpty()) {
            call.reject("Parameter 'id' is required");
            return;
        }

        int width = call.getInt("width", PhotoLibraryDefaults.THUMBNAIL_WIDTH);
        int height = call.getInt("height", PhotoLibraryDefaults.THUMBNAIL_HEIGHT);
        double quality = call.getDouble("quality", PhotoLibraryDefaults.THUMBNAIL_QUALITY);

        executor.execute(() -> {
            try {
                JSObject file = service.getThumbnailFile(id, width, height, quality);
                if (file == null) {
                    call.reject(PhotoLibraryService.ASSET_NOT_FOUND);
                    return;
                }
                call.resolve(file);
            } catch (Exception ex) {
                call.reject(ex.getMessage(), ex);
            }
        });
    }

    private JSObject statusObject(@NonNull String state) {
        JSObject result = new JSObject();
        result.put("state", state);
        return result;
    }

    private boolean hasMediaPermissions() {
        return hasPermission(permissionAlias());
    }

    private String currentAuthorizationState() {
        return hasMediaPermissions() ? STATE_AUTHORIZED : STATE_DENIED;
    }

    private String permissionAlias() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ? PERMISSION_MEDIA : PERMISSION_MEDIA_LEGACY;
    }
}
