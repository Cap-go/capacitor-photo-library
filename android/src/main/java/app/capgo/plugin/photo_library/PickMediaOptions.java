package app.capgo.plugin.photo_library;

import com.getcapacitor.PluginCall;

final class PickMediaOptions {

    final int selectionLimit;
    final boolean includeImages;
    final boolean includeVideos;
    final int thumbnailWidth;
    final int thumbnailHeight;
    final double thumbnailQuality;

    private PickMediaOptions(
        int selectionLimit,
        boolean includeImages,
        boolean includeVideos,
        int thumbnailWidth,
        int thumbnailHeight,
        double thumbnailQuality
    ) {
        this.selectionLimit = selectionLimit;
        this.includeImages = includeImages;
        this.includeVideos = includeVideos;
        this.thumbnailWidth = thumbnailWidth;
        this.thumbnailHeight = thumbnailHeight;
        this.thumbnailQuality = thumbnailQuality;
    }

    static PickMediaOptions fromCall(PluginCall call) {
        int limit = call.getInt("selectionLimit", 1);
        if (limit < 0) {
            throw new IllegalArgumentException("selectionLimit must be greater than or equal to 0");
        }

        boolean includeImages = call.getBoolean("includeImages", true);
        boolean includeVideos = call.getBoolean("includeVideos", false);
        if (!includeImages && !includeVideos) {
            includeImages = true;
        }

        int thumbnailWidth = Math.max(0, call.getInt("thumbnailWidth", 256));
        int thumbnailHeight = Math.max(0, call.getInt("thumbnailHeight", 256));

        Double qualityOption = call.getDouble("thumbnailQuality");
        double thumbnailQuality = qualityOption != null ? qualityOption : 0.7;
        thumbnailQuality = Math.max(0.0, Math.min(1.0, thumbnailQuality));

        return new PickMediaOptions(limit, includeImages, includeVideos, thumbnailWidth, thumbnailHeight, thumbnailQuality);
    }
}
