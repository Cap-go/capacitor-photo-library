package app.capgo.plugin.photo_library;

import com.getcapacitor.PluginCall;

final class GetLibraryOptions {

    final int offset;
    final Integer limit;
    final boolean includeImages;
    final boolean includeVideos;
    final boolean includeAlbumData;
    final boolean includeCloudData;
    final boolean useOriginalFileNames;
    final int thumbnailWidth;
    final int thumbnailHeight;
    final double thumbnailQuality;
    final boolean includeFullResolutionData;

    private GetLibraryOptions(
        int offset,
        Integer limit,
        boolean includeImages,
        boolean includeVideos,
        boolean includeAlbumData,
        boolean includeCloudData,
        boolean useOriginalFileNames,
        int thumbnailWidth,
        int thumbnailHeight,
        double thumbnailQuality,
        boolean includeFullResolutionData
    ) {
        this.offset = offset;
        this.limit = limit;
        this.includeImages = includeImages;
        this.includeVideos = includeVideos;
        this.includeAlbumData = includeAlbumData;
        this.includeCloudData = includeCloudData;
        this.useOriginalFileNames = useOriginalFileNames;
        this.thumbnailWidth = thumbnailWidth;
        this.thumbnailHeight = thumbnailHeight;
        this.thumbnailQuality = thumbnailQuality;
        this.includeFullResolutionData = includeFullResolutionData;
    }

    static GetLibraryOptions fromCall(PluginCall call) {
        int offset = call.getInt("offset", 0);
        if (offset < 0) {
            throw new IllegalArgumentException("offset must be greater than or equal to 0");
        }

        Integer limit = null;
        Integer limitValue = call.getInt("limit");
        if (limitValue != null) {
            if (limitValue < 0) {
                throw new IllegalArgumentException("limit must be greater than or equal to 0");
            }
            if (limitValue > 0) {
                limit = limitValue;
            }
        }

        boolean includeImages = call.getBoolean("includeImages", true);
        boolean includeVideos = call.getBoolean("includeVideos", false);
        if (!includeImages && !includeVideos) {
            includeImages = true;
        }

        boolean includeAlbumData = call.getBoolean("includeAlbumData", false);
        boolean includeCloudData = call.getBoolean("includeCloudData", true);
        boolean useOriginalFileNames = call.getBoolean("useOriginalFileNames", false);

        int thumbnailWidth = Math.max(0, call.getInt("thumbnailWidth", PhotoLibraryDefaults.THUMBNAIL_WIDTH));
        int thumbnailHeight = Math.max(0, call.getInt("thumbnailHeight", PhotoLibraryDefaults.THUMBNAIL_HEIGHT));

        Double qualityOption = call.getDouble("thumbnailQuality");
        double thumbnailQuality = qualityOption != null ? qualityOption : PhotoLibraryDefaults.THUMBNAIL_QUALITY;
        thumbnailQuality = Math.max(0.0, Math.min(1.0, thumbnailQuality));

        boolean includeFullResolutionData = call.getBoolean("includeFullResolutionData", false);

        return new GetLibraryOptions(
            offset,
            limit,
            includeImages,
            includeVideos,
            includeAlbumData,
            includeCloudData,
            useOriginalFileNames,
            thumbnailWidth,
            thumbnailHeight,
            thumbnailQuality,
            includeFullResolutionData
        );
    }
}
