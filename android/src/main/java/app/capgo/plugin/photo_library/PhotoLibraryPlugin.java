package app.capgo.plugin.photo_library;

import android.Manifest;
import android.app.Activity;
import android.content.ClipData;
import android.content.ContentResolver;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import androidx.activity.result.ActivityResult;
import androidx.annotation.NonNull;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.ActivityCallback;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
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

    private final String pluginVersion = "7.2.10";

    static final String PERMISSION_MEDIA = "media";
    static final String PERMISSION_MEDIA_LEGACY = "media_legacy";

    private static final String STATE_AUTHORIZED = "authorized";
    private static final String STATE_DENIED = "denied";

    private final ExecutorService executor = Executors.newFixedThreadPool(2);
    private PhotoLibraryService service;
    private boolean pickInProgress = false;
    private PickMediaOptions pendingPickOptions;

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

    @PluginMethod
    public void pickMedia(PluginCall call) {
        if (pickInProgress) {
            call.reject("Another pickMedia call is already in progress");
            return;
        }

        PickMediaOptions options;
        try {
            options = PickMediaOptions.fromCall(call);
        } catch (IllegalArgumentException ex) {
            call.reject(ex.getMessage());
            return;
        }

        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        if (options.includeImages && options.includeVideos) {
            intent.setType("*/*");
            intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[] { "image/*", "video/*" });
        } else if (options.includeVideos) {
            intent.setType("video/*");
        } else {
            intent.setType("image/*");
        }
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, options.selectionLimit == 0 || options.selectionLimit > 1);
        intent.putExtra(Intent.EXTRA_LOCAL_ONLY, true);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);

        pickInProgress = true;
        pendingPickOptions = options;
        bridge.saveCall(call);
        startActivityForResult(call, intent, "handlePickMedia");
    }

    @ActivityCallback
    private void handlePickMedia(PluginCall call, ActivityResult result) {
        PickMediaOptions options = pendingPickOptions;
        pendingPickOptions = null;
        pickInProgress = false;

        if (call == null) {
            return;
        }

        JSObject response = new JSObject();
        JSArray assets = new JSArray();

        if (options == null || result == null || result.getResultCode() != Activity.RESULT_OK) {
            try {
                response.put("assets", assets);
            } catch (Exception ignored) {}
            call.resolve(response);
            return;
        }

        Intent data = result.getData();
        if (data == null) {
            try {
                response.put("assets", assets);
            } catch (Exception ignored) {}
            call.resolve(response);
            return;
        }

        List<Uri> uris = new ArrayList<>();
        ClipData clipData = data.getClipData();
        if (clipData != null) {
            for (int i = 0; i < clipData.getItemCount(); i++) {
                ClipData.Item item = clipData.getItemAt(i);
                Uri uri = item.getUri();
                if (uri != null) {
                    uris.add(uri);
                }
            }
        } else {
            Uri single = data.getData();
            if (single != null) {
                uris.add(single);
            }
        }

        if (uris.isEmpty()) {
            try {
                response.put("assets", assets);
            } catch (Exception ignored) {}
            call.resolve(response);
            return;
        }

        if (options.selectionLimit > 0 && uris.size() > options.selectionLimit) {
            uris = new ArrayList<>(uris.subList(0, options.selectionLimit));
        }

        ContentResolver resolver = getContext().getContentResolver();
        int flags = data.getFlags() & (Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        if (flags != 0) {
            for (Uri uri : uris) {
                try {
                    resolver.takePersistableUriPermission(uri, flags);
                } catch (SecurityException ignored) {}
            }
        }

        final List<Uri> finalUris = uris;
        executor.execute(() -> {
            try {
                JSArray pickedAssets = service.createAssetsFromUris(finalUris, options);
                JSObject resultObject = new JSObject();
                resultObject.put("assets", pickedAssets);
                bridge.executeOnMainThread(() -> call.resolve(resultObject));
            } catch (IOException ex) {
                bridge.executeOnMainThread(() -> call.reject(ex.getMessage(), ex));
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

    @PluginMethod
    public void getPluginVersion(final PluginCall call) {
        try {
            final JSObject ret = new JSObject();
            ret.put("version", this.pluginVersion);
            call.resolve(ret);
        } catch (final Exception e) {
            call.reject("Could not get plugin version", e);
        }
    }
}
