package app.capgo.plugin.photo_library;

import android.content.ContentResolver;
import android.graphics.Bitmap;
import android.graphics.ImageDecoder;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import androidx.annotation.Nullable;
import java.io.IOException;
import java.util.Locale;

/**
 * Thumbnail sizing and cache naming. Aspect-fill matches iOS {@code contentMode: .aspectFill}.
 */
final class ThumbnailHelper {

    /**
     * Bumped when thumbnail generation semantics change so cached files are not reused.
     */
    static final int CACHE_KEY_VERSION = 2;

    private ThumbnailHelper() {}

    static String thumbnailCacheFileName(String hashedId, int width, int height, int qualityPercent) {
        return String.format(Locale.US, "%s_v%d_%dx%d_q%d.jpg", hashedId, CACHE_KEY_VERSION, width, height, qualityPercent);
    }

    static float aspectFillScale(int targetWidth, int targetHeight, int sourceWidth, int sourceHeight) {
        if (sourceWidth <= 0 || sourceHeight <= 0) {
            return 1f;
        }
        return Math.max((float) targetWidth / sourceWidth, (float) targetHeight / sourceHeight);
    }

    static int[] aspectFillDimensions(int targetWidth, int targetHeight, int sourceWidth, int sourceHeight) {
        float scale = aspectFillScale(targetWidth, targetHeight, sourceWidth, sourceHeight);
        return new int[] { Math.round(sourceWidth * scale), Math.round(sourceHeight * scale) };
    }

    /**
     * Downsampled decode size for {@link ImageDecoder} so the bitmap is at least as large as the
     * aspect-fill target box without decoding full resolution.
     */
    static int[] imageDecoderTargetSize(int sourceWidth, int sourceHeight, int targetWidth, int targetHeight) {
        float scale = aspectFillScale(targetWidth, targetHeight, sourceWidth, sourceHeight);
        if (scale >= 1f) {
            return new int[] { sourceWidth, sourceHeight };
        }
        return new int[] { Math.round(sourceWidth * scale), Math.round(sourceHeight * scale) };
    }

    /**
     * Decode an image from the original file. Avoids MediaStore {@code loadThumbnail} crops on some devices.
     * Returns null on failure or API &lt; 28.
     */
    @Nullable
    static Bitmap decodeImageFromOriginal(ContentResolver resolver, Uri uri, int targetWidth, int targetHeight) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return null;
        }
        try {
            return ImageDecoder.decodeBitmap(ImageDecoder.createSource(resolver, uri), (decoder, info, source) -> {
                int sourceWidth = info.getSize().getWidth();
                int sourceHeight = info.getSize().getHeight();
                int[] target = imageDecoderTargetSize(sourceWidth, sourceHeight, targetWidth, targetHeight);
                if (target[0] != sourceWidth || target[1] != sourceHeight) {
                    decoder.setTargetSize(target[0], target[1]);
                }
                decoder.setAllocator(ImageDecoder.ALLOCATOR_SOFTWARE);
            });
        } catch (IOException e) {
            return null;
        }
    }

    @Nullable
    static Bitmap scaleAspectFill(Bitmap bitmap, int targetWidth, int targetHeight) {
        if (bitmap == null) {
            return null;
        }
        int[] dims = aspectFillDimensions(targetWidth, targetHeight, bitmap.getWidth(), bitmap.getHeight());
        if (dims[0] == bitmap.getWidth() && dims[1] == bitmap.getHeight()) {
            return bitmap;
        }
        Bitmap scaled = Bitmap.createScaledBitmap(bitmap, dims[0], dims[1], true);
        if (scaled != bitmap) {
            bitmap.recycle();
        }
        return scaled;
    }

    static boolean isImageMediaType(int mediaType) {
        return mediaType == MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE;
    }
}
