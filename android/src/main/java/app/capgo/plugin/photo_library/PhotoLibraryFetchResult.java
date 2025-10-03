package app.capgo.plugin.photo_library;

import com.getcapacitor.JSArray;

final class PhotoLibraryFetchResult {

    final JSArray assets;
    final int totalCount;
    final boolean hasMore;

    PhotoLibraryFetchResult(JSArray assets, int totalCount, boolean hasMore) {
        this.assets = assets;
        this.totalCount = totalCount;
        this.hasMore = hasMore;
    }
}
