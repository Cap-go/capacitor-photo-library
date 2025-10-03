package app.capgo.plugin.photo_library;

import android.content.ContentResolver;
import android.content.ContentUris;
import android.content.Context;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.MediaMetadataRetriever;
import android.media.ThumbnailUtils;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.util.Size;
import androidx.annotation.Nullable;
import com.getcapacitor.Bridge;
import com.getcapacitor.FileUtils;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Logger;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

final class PhotoLibraryService {

    static final String PERMISSION_ERROR = "Permission Denial: This application is not allowed to access photo data.";
    static final String ASSET_NOT_FOUND = "Asset not found";

    private final Context context;
    private final Bridge bridge;
    private final ContentResolver resolver;
    private final File cacheRoot;
    private final File thumbnailDirectory;
    private final File fileDirectory;
    private final DateTimeFormatter isoFormatter;
    private final Map<String, PickedItem> pickedItems = new ConcurrentHashMap<>();

    PhotoLibraryService(Context context, Bridge bridge) {
        this.context = context.getApplicationContext();
        this.bridge = bridge;
        this.resolver = context.getContentResolver();
        this.cacheRoot = new File(context.getCacheDir(), "photoLibrary");
        this.thumbnailDirectory = new File(cacheRoot, "thumbnails");
        this.fileDirectory = new File(cacheRoot, "files");
        this.isoFormatter = DateTimeFormatter.ISO_OFFSET_DATE_TIME.withZone(ZoneOffset.UTC);
    }

    void prepareCacheDirectories() {
        if (!cacheRoot.exists()) {
            cacheRoot.mkdirs();
        }
        if (!thumbnailDirectory.exists()) {
            thumbnailDirectory.mkdirs();
        }
        if (!fileDirectory.exists()) {
            fileDirectory.mkdirs();
        }
    }

    JSArray fetchAlbums() {
        Map<String, AlbumAccumulator> accumulator = new HashMap<>();
        queryAlbums(getImagesUri(), accumulator);
        queryAlbums(getVideosUri(), accumulator);

        JSArray array = new JSArray();
        for (AlbumAccumulator album : accumulator.values()) {
            JSObject obj = new JSObject();
            obj.put("id", album.id);
            obj.put("title", album.title);
            obj.put("assetCount", album.count);
            array.put(obj);
        }
        return array;
    }

    PhotoLibraryFetchResult fetchLibrary(GetLibraryOptions options) throws IOException {
        Uri contentUri = getFilesUri();
        String[] projection = new String[] {
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.DISPLAY_NAME,
            MediaStore.Files.FileColumns.MIME_TYPE,
            MediaStore.Files.FileColumns.MEDIA_TYPE,
            MediaStore.Files.FileColumns.SIZE,
            MediaStore.Files.FileColumns.DATE_ADDED,
            MediaStore.Files.FileColumns.DATE_MODIFIED,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
            MediaStore.Video.Media.DURATION,
            MediaStore.Images.Media.BUCKET_ID,
            MediaStore.Images.Media.BUCKET_DISPLAY_NAME
        };

        Selection selection = buildSelection(options);
        int totalCount = countItems(contentUri, selection);

        String sortOrder = buildSortOrder(options);
        JSArray assetsArray = new JSArray();
        int collected = 0;
        int skipped = 0;

        try (Cursor cursor = resolver.query(contentUri, projection, selection.selection, selection.args, sortOrder)) {
            if (cursor != null) {
                while (cursor.moveToNext()) {
                    if (options.limit == null && options.offset > 0 && skipped < options.offset) {
                        skipped++;
                        continue;
                    }
                    if (options.limit != null && collected >= options.limit) {
                        break;
                    }
                    JSObject asset = buildAsset(cursor, options);
                    if (asset != null) {
                        assetsArray.put(asset);
                        collected++;
                    }
                }
            }
        }

        int consumed = options.limit != null ? options.offset + collected : Math.min(totalCount, options.offset) + collected;
        boolean hasMore = consumed < totalCount;
        return new PhotoLibraryFetchResult(assetsArray, totalCount, hasMore);
    }

    JSArray createAssetsFromUris(List<Uri> uris, PickMediaOptions options) throws IOException {
        JSArray array = new JSArray();
        for (Uri uri : uris) {
            JSObject asset = createAssetFromUri(uri, options);
            if (asset != null) {
                try {
                    array.put(asset);
                } catch (Exception e) {
                    Logger.error("PhotoLibrary", "Failed to add picked asset", e);
                }
            }
        }
        return array;
    }

    @Nullable
    private JSObject createAssetFromUri(Uri uri, PickMediaOptions options) throws IOException {
        InputStream stream = resolver.openInputStream(uri);
        if (stream == null) {
            return null;
        }

        String mimeType = resolver.getType(uri);
        String type = (mimeType != null && mimeType.startsWith("video")) ? "video" : "image";
        String identifier = "picked:" + UUID.randomUUID();

        String displayName = null;
        long reportedSize = -1;
        try (Cursor cursor = resolver.query(uri, new String[] { OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE }, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (nameIndex != -1) {
                    displayName = cursor.getString(nameIndex);
                }
                int sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE);
                if (sizeIndex != -1) {
                    reportedSize = cursor.getLong(sizeIndex);
                }
            }
        }

        String extension = guessExtension(mimeType);
        File file = new File(fileDirectory, hashed(identifier) + extension);
        try (InputStream in = stream; FileOutputStream out = new FileOutputStream(file)) {
            byte[] buffer = new byte[8192];
            int read;
            while ((read = in.read(buffer)) != -1) {
                out.write(buffer, 0, read);
            }
        }

        long size = file.length();
        if (size <= 0 && reportedSize > 0) {
            size = reportedSize;
        }

        int width = 0;
        int height = 0;
        Double durationSeconds = null;

        if ("image".equals(type)) {
            BitmapFactory.Options opts = new BitmapFactory.Options();
            opts.inJustDecodeBounds = true;
            BitmapFactory.decodeFile(file.getAbsolutePath(), opts);
            width = opts.outWidth;
            height = opts.outHeight;
        } else if ("video".equals(type)) {
            MediaMetadataRetriever retriever = new MediaMetadataRetriever();
            try {
                retriever.setDataSource(file.getAbsolutePath());
                String widthVal = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH);
                String heightVal = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT);
                String rotationVal = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION);
                String durationVal = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION);

                if (widthVal != null) {
                    width = Integer.parseInt(widthVal);
                }
                if (heightVal != null) {
                    height = Integer.parseInt(heightVal);
                }
                if (rotationVal != null) {
                    int rotation = Integer.parseInt(rotationVal);
                    if (rotation == 90 || rotation == 270) {
                        int tmp = width;
                        width = height;
                        height = tmp;
                    }
                }
                if (durationVal != null) {
                    long durationMs = Long.parseLong(durationVal);
                    durationSeconds = durationMs / 1000.0;
                }
            } catch (Exception ignored) {} finally {
                retriever.release();
            }
        }

        String resolvedMime = mimeType != null ? mimeType : ("image".equals(type) ? "image/jpeg" : "application/octet-stream");
        PickedItem picked = new PickedItem(file, resolvedMime, type);
        pickedItems.put(identifier, picked);

        JSObject asset = new JSObject();
        try {
            asset.put("id", identifier);
            asset.put("fileName", displayName != null ? displayName : identifier + extension);
            asset.put("type", type);
            asset.put("width", width);
            asset.put("height", height);
            if (durationSeconds != null) {
                asset.put("duration", durationSeconds);
            }
            asset.put("mimeType", resolvedMime);
            asset.put("size", size);

            JSObject fileObject = createFileObject(file, resolvedMime);
            asset.put("file", fileObject);

            JSObject thumbnail = ensurePickedThumbnail(
                identifier,
                picked,
                options.thumbnailWidth,
                options.thumbnailHeight,
                options.thumbnailQuality
            );
            if (thumbnail != null) {
                asset.put("thumbnail", thumbnail);
            }
        } catch (Exception e) {
            Logger.error("PhotoLibrary", "Failed to build picked asset", e);
            pickedItems.remove(identifier);
            if (file.exists()) {
                //noinspection ResultOfMethodCallIgnored
                file.delete();
            }
            return null;
        }

        return asset;
    }

    @Nullable
    JSObject getFullResolutionFile(String assetId) throws IOException {
        PickedItem picked = pickedItems.get(assetId);
        if (picked != null) {
            return createFileObject(picked.file, picked.mimeType);
        }

        MediaAsset asset = findAsset(assetId);
        if (asset == null) {
            return null;
        }

        File file = ensureFullFile(asset);
        if (file == null) {
            return null;
        }
        long size = file.length();
        JSObject result = new JSObject();
        result.put("path", file.getAbsolutePath());
        result.put("webPath", portablePath(file));
        result.put("mimeType", asset.mimeType);
        result.put("size", size);
        return result;
    }

    @Nullable
    JSObject getThumbnailFile(String assetId, int width, int height, double quality) throws IOException {
        PickedItem picked = pickedItems.get(assetId);
        if (picked != null) {
            return ensurePickedThumbnail(assetId, picked, width, height, quality);
        }

        MediaAsset asset = findAsset(assetId);
        if (asset == null) {
            return null;
        }
        if (width <= 0 || height <= 0) {
            return null;
        }

        File file = ensureThumbnail(asset, width, height, quality);
        if (file == null) {
            return null;
        }
        long size = file.length();
        JSObject result = new JSObject();
        result.put("path", file.getAbsolutePath());
        result.put("webPath", portablePath(file));
        result.put("mimeType", "image/jpeg");
        result.put("size", size);
        return result;
    }

    private void queryAlbums(Uri uri, Map<String, AlbumAccumulator> accumulator) {
        String[] projection = new String[] { MediaStore.Images.Media.BUCKET_ID, MediaStore.Images.Media.BUCKET_DISPLAY_NAME };

        try (Cursor cursor = resolver.query(uri, projection, null, null, null)) {
            if (cursor == null) {
                return;
            }
            int idxId = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.BUCKET_ID);
            int idxName = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.BUCKET_DISPLAY_NAME);
            while (cursor.moveToNext()) {
                String bucketId = cursor.getString(idxId);
                if (bucketId == null) {
                    continue;
                }
                String title = cursor.getString(idxName);
                AlbumAccumulator album = accumulator.get(bucketId);
                if (album == null) {
                    album = new AlbumAccumulator(bucketId, title == null ? "" : title);
                    accumulator.put(bucketId, album);
                }
                album.count += 1;
            }
        }
    }

    private Selection buildSelection(GetLibraryOptions options) {
        StringBuilder selection = new StringBuilder();
        List<String> args = new ArrayList<>();

        if (options.includeImages && options.includeVideos) {
            selection
                .append("(")
                .append(MediaStore.Files.FileColumns.MEDIA_TYPE)
                .append("=? OR ")
                .append(MediaStore.Files.FileColumns.MEDIA_TYPE)
                .append("=? )");
            args.add(String.valueOf(MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE));
            args.add(String.valueOf(MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO));
        } else if (options.includeImages) {
            selection.append(MediaStore.Files.FileColumns.MEDIA_TYPE).append("=?");
            args.add(String.valueOf(MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE));
        } else {
            selection.append(MediaStore.Files.FileColumns.MEDIA_TYPE).append("=?");
            args.add(String.valueOf(MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO));
        }

        return new Selection(selection.toString(), args.toArray(new String[0]));
    }

    private int countItems(Uri uri, Selection selection) {
        int count = 0;
        try (
            Cursor cursor = resolver.query(
                uri,
                new String[] { MediaStore.Files.FileColumns._ID },
                selection.selection,
                selection.args,
                null
            )
        ) {
            if (cursor != null) {
                count = cursor.getCount();
            }
        }
        return count;
    }

    private String buildSortOrder(GetLibraryOptions options) {
        StringBuilder builder = new StringBuilder(MediaStore.MediaColumns.DATE_ADDED + " DESC");
        if (options.limit != null) {
            builder.append(" LIMIT ").append(options.limit);
            if (options.offset > 0) {
                builder.append(" OFFSET ").append(options.offset);
            }
        }
        return builder.toString();
    }

    private JSObject buildAsset(Cursor cursor, GetLibraryOptions options) throws IOException {
        int mediaType = cursor.getInt(cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MEDIA_TYPE));
        if (mediaType != MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE && mediaType != MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO) {
            return null;
        }

        long id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID));
        String mimeType = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MIME_TYPE));
        String displayName = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME));
        long size = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.SIZE));

        long dateTaken = getLong(cursor, MediaStore.Images.Media.DATE_TAKEN);
        if (dateTaken <= 0) {
            long dateAdded = getLong(cursor, MediaStore.Files.FileColumns.DATE_ADDED);
            dateTaken = dateAdded > 0 ? dateAdded * 1000 : 0;
        }
        long dateModified = getLong(cursor, MediaStore.Files.FileColumns.DATE_MODIFIED);
        if (dateModified > 0) {
            dateModified = dateModified * 1000;
        }

        int width = getInt(cursor, MediaStore.Images.Media.WIDTH);
        int height = getInt(cursor, MediaStore.Images.Media.HEIGHT);
        long duration = mediaType == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO ? getLong(cursor, MediaStore.Video.Media.DURATION) : 0;

        String bucketId = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Images.Media.BUCKET_ID));

        Uri assetUri = contentUriFor(mediaType, id);
        if (assetUri == null) {
            return null;
        }

        String assetType = mediaType == MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE ? "image" : "video";
        String identifier = assetType + ":" + id;

        MediaAsset assetInfo = new MediaAsset(identifier, assetUri, mediaType, mimeType, displayName);

        JSObject asset = new JSObject();
        asset.put("id", identifier);
        asset.put("fileName", displayName != null ? displayName : (identifier + guessExtension(mimeType)));
        asset.put("type", assetType);
        asset.put("width", width);
        asset.put("height", height);
        asset.put("mimeType", mimeType != null ? mimeType : "application/octet-stream");
        if (duration > 0) {
            asset.put("duration", duration / 1000.0);
        }
        if (dateTaken > 0) {
            asset.put("creationDate", isoFormatter.format(Instant.ofEpochMilli(dateTaken)));
        }
        if (dateModified > 0) {
            asset.put("modificationDate", isoFormatter.format(Instant.ofEpochMilli(dateModified)));
        }
        if (bucketId != null && options.includeAlbumData) {
            JSArray albums = new JSArray();
            albums.put(bucketId);
            asset.put("albumIds", albums);
        }

        JSObject thumbnail = null;
        if (options.thumbnailWidth > 0 && options.thumbnailHeight > 0) {
            File thumb = ensureThumbnail(assetInfo, options.thumbnailWidth, options.thumbnailHeight, options.thumbnailQuality);
            if (thumb != null) {
                thumbnail = new JSObject();
                thumbnail.put("path", thumb.getAbsolutePath());
                thumbnail.put("webPath", portablePath(thumb));
                thumbnail.put("mimeType", "image/jpeg");
                thumbnail.put("size", thumb.length());
            }
        }
        if (thumbnail != null) {
            asset.put("thumbnail", thumbnail);
        }

        if (options.includeFullResolutionData) {
            File full = ensureFullFile(assetInfo);
            if (full != null) {
                JSObject file = new JSObject();
                file.put("path", full.getAbsolutePath());
                file.put("webPath", portablePath(full));
                file.put("mimeType", mimeType != null ? mimeType : "application/octet-stream");
                file.put("size", full.length());
                asset.put("file", file);
            }
        }

        asset.put("size", size);

        return asset;
    }

    @Nullable
    private MediaAsset findAsset(String identifier) {
        ParsedIdentifier parsed = ParsedIdentifier.parse(identifier);
        if (parsed == null) {
            return null;
        }

        Uri uri = contentUriFor(parsed.mediaType, parsed.id);
        if (uri == null) {
            return null;
        }

        String[] projection = new String[] { MediaStore.Files.FileColumns.DISPLAY_NAME, MediaStore.Files.FileColumns.MIME_TYPE };

        String selection = MediaStore.Files.FileColumns._ID + "=?";
        String[] args = new String[] { String.valueOf(parsed.id) };

        try (Cursor cursor = resolver.query(getFilesUri(), projection, selection, args, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                String displayName = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME));
                String mimeType = cursor.getString(cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MIME_TYPE));
                return new MediaAsset(identifier, uri, parsed.mediaType, mimeType, displayName);
            }
        }
        return null;
    }

    @Nullable
    private File ensureFullFile(MediaAsset asset) throws IOException {
        String extension = guessExtension(asset.mimeType);
        File target = new File(fileDirectory, hashed(asset.identifier) + extension);
        if (target.exists()) {
            return target;
        }

        try (InputStream in = resolver.openInputStream(asset.uri)) {
            if (in == null) {
                return null;
            }
            try (FileOutputStream out = new FileOutputStream(target)) {
                byte[] buffer = new byte[8192];
                int read;
                while ((read = in.read(buffer)) != -1) {
                    out.write(buffer, 0, read);
                }
            }
        }

        return target;
    }

    @Nullable
    private File ensureThumbnail(MediaAsset asset, int width, int height, double quality) throws IOException {
        int qualityPercent = (int) Math.max(0, Math.min(100, Math.round(quality * 100)));
        String name = String.format(Locale.US, "%s_%dx%d_q%d.jpg", hashed(asset.identifier), width, height, qualityPercent);
        File target = new File(thumbnailDirectory, name);
        if (target.exists()) {
            return target;
        }

        Bitmap bitmap = null;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                bitmap = resolver.loadThumbnail(asset.uri, new Size(width, height), null);
            } catch (IOException e) {
                Logger.debug("PhotoLibrary", "loadThumbnail failed: " + e.getMessage());
            }
        }

        if (bitmap == null) {
            ParsedIdentifier parsed = ParsedIdentifier.parse(asset.identifier);
            if (parsed != null) {
                long id = parsed.id;
                if (asset.mediaType == MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE) {
                    bitmap = MediaStore.Images.Thumbnails.getThumbnail(resolver, id, MediaStore.Images.Thumbnails.MINI_KIND, null);
                } else if (asset.mediaType == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO) {
                    bitmap = MediaStore.Video.Thumbnails.getThumbnail(resolver, id, MediaStore.Video.Thumbnails.MINI_KIND, null);
                }
            }
        }

        if (bitmap == null) {
            return null;
        }

        Bitmap scaled = Bitmap.createScaledBitmap(bitmap, width, height, true);
        if (bitmap != scaled) {
            bitmap.recycle();
        }

        try (FileOutputStream out = new FileOutputStream(target)) {
            scaled.compress(Bitmap.CompressFormat.JPEG, qualityPercent, out);
        } finally {
            scaled.recycle();
        }

        return target;
    }

    private Uri contentUriFor(int mediaType, long id) {
        if (mediaType == MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE) {
            return ContentUris.withAppendedId(getImagesUri(), id);
        } else if (mediaType == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO) {
            return ContentUris.withAppendedId(getVideosUri(), id);
        }
        return null;
    }

    private Uri getImagesUri() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL);
        }
        return MediaStore.Images.Media.EXTERNAL_CONTENT_URI;
    }

    private Uri getVideosUri() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL);
        }
        return MediaStore.Video.Media.EXTERNAL_CONTENT_URI;
    }

    private Uri getFilesUri() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL);
        }
        return MediaStore.Files.getContentUri("external");
    }

    private long getLong(Cursor cursor, String column) {
        int index = cursor.getColumnIndex(column);
        if (index == -1) {
            return 0;
        }
        return cursor.getLong(index);
    }

    private int getInt(Cursor cursor, String column) {
        int index = cursor.getColumnIndex(column);
        if (index == -1) {
            return 0;
        }
        return cursor.getInt(index);
    }

    private JSObject createFileObject(File file, String mimeType) {
        JSObject result = new JSObject();
        try {
            result.put("path", file.getAbsolutePath());
            result.put("webPath", portablePath(file));
            result.put("mimeType", mimeType != null ? mimeType : "application/octet-stream");
            result.put("size", file.length());
        } catch (Exception e) {
            Logger.error("PhotoLibrary", "Failed to serialize file", e);
        }
        return result;
    }

    private JSObject ensurePickedThumbnail(String identifier, PickedItem picked, int width, int height, double quality) throws IOException {
        if (width <= 0 || height <= 0) {
            return null;
        }

        File target = new File(
            thumbnailDirectory,
            String.format(Locale.US, "%s_%dx%d_q%.0f.jpg", hashed(identifier), width, height, quality * 100)
        );

        if (!target.exists()) {
            if ("image".equals(picked.type)) {
                Bitmap bitmap = BitmapFactory.decodeFile(picked.file.getAbsolutePath());
                if (bitmap == null) {
                    return null;
                }
                Bitmap scaled = Bitmap.createScaledBitmap(bitmap, width, height, true);
                if (scaled != bitmap) {
                    bitmap.recycle();
                }
                try (FileOutputStream out = new FileOutputStream(target)) {
                    scaled.compress(Bitmap.CompressFormat.JPEG, (int) Math.round(Math.max(0, Math.min(1, quality)) * 100), out);
                }
                scaled.recycle();
            } else if ("video".equals(picked.type)) {
                Bitmap bitmap;
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    bitmap = ThumbnailUtils.createVideoThumbnail(picked.file, new Size(width, height), null);
                } else {
                    bitmap = ThumbnailUtils.createVideoThumbnail(picked.file.getAbsolutePath(), MediaStore.Video.Thumbnails.MINI_KIND);
                    if (bitmap != null && (bitmap.getWidth() != width || bitmap.getHeight() != height)) {
                        Bitmap rescaled = Bitmap.createScaledBitmap(bitmap, width, height, true);
                        if (rescaled != bitmap) {
                            bitmap.recycle();
                        }
                        bitmap = rescaled;
                    }
                }

                if (bitmap == null) {
                    return null;
                }

                try (FileOutputStream out = new FileOutputStream(target)) {
                    bitmap.compress(Bitmap.CompressFormat.JPEG, (int) Math.round(Math.max(0, Math.min(1, quality)) * 100), out);
                } finally {
                    bitmap.recycle();
                }
            } else {
                return null;
            }
        }

        return createFileObject(target, "image/jpeg");
    }

    private String portablePath(File file) {
        String host = bridge.getLocalUrl();
        if (host == null || host.isEmpty()) {
            return Uri.fromFile(file).toString();
        }
        return FileUtils.getPortablePath(context, host, Uri.fromFile(file));
    }

    private String hashed(String input) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] encoded = digest.digest(input.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (byte b : encoded) {
                sb.append(String.format(Locale.US, "%02x", b));
            }
            return sb.toString();
        } catch (NoSuchAlgorithmException e) {
            return String.valueOf(input.hashCode());
        }
    }

    private String guessExtension(@Nullable String mimeType) {
        if (mimeType == null) {
            return ".dat";
        }
        if (mimeType.equals("image/jpeg")) {
            return ".jpg";
        } else if (mimeType.equals("image/png")) {
            return ".png";
        } else if (mimeType.equals("image/gif")) {
            return ".gif";
        } else if (mimeType.equals("video/mp4")) {
            return ".mp4";
        } else if (mimeType.equals("video/quicktime")) {
            return ".mov";
        }
        String subtype = mimeType.substring(mimeType.indexOf('/') + 1);
        return "." + subtype;
    }

    private static final class PickedItem {

        final File file;
        final String mimeType;
        final String type;

        PickedItem(File file, String mimeType, String type) {
            this.file = file;
            this.mimeType = mimeType;
            this.type = type;
        }
    }

    private static final class AlbumAccumulator {

        final String id;
        final String title;
        int count;

        AlbumAccumulator(String id, String title) {
            this.id = id;
            this.title = title;
            this.count = 0;
        }
    }

    private static final class Selection {

        final String selection;
        final String[] args;

        Selection(String selection, String[] args) {
            this.selection = selection;
            this.args = args;
        }
    }

    private static final class ParsedIdentifier {

        final long id;
        final int mediaType;

        private ParsedIdentifier(long id, int mediaType) {
            this.id = id;
            this.mediaType = mediaType;
        }

        static ParsedIdentifier parse(String identifier) {
            if (identifier == null) {
                return null;
            }
            String[] parts = identifier.split(":");
            if (parts.length != 2) {
                return null;
            }
            try {
                long id = Long.parseLong(parts[1]);
                int mediaType = "video".equals(parts[0])
                    ? MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
                    : MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE;
                return new ParsedIdentifier(id, mediaType);
            } catch (NumberFormatException ex) {
                return null;
            }
        }
    }

    private static final class MediaAsset {

        final String identifier;
        final Uri uri;
        final int mediaType;
        final String mimeType;
        final String displayName;

        MediaAsset(String identifier, Uri uri, int mediaType, String mimeType, String displayName) {
            this.identifier = identifier;
            this.uri = uri;
            this.mediaType = mediaType;
            this.mimeType = mimeType;
            this.displayName = displayName;
        }
    }
}
