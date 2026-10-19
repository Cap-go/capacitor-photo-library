package app.capgo.plugin.photo_library;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class ThumbnailHelperTest {

    @Test
    public void aspectFillScale_portraitPhotoInSquareTarget_usesHeightLimitingScale() {
        float scale = ThumbnailHelper.aspectFillScale(300, 300, 2250, 4000);
        assertEquals(300f / 2250f, scale, 0.0001f);
    }

    @Test
    public void aspectFillScale_landscapePhotoInSquareTarget_usesWidthLimitingScale() {
        float scale = ThumbnailHelper.aspectFillScale(300, 300, 4000, 2250);
        assertEquals(300f / 2250f, scale, 0.0001f);
    }

    @Test
    public void aspectFillDimensions_squareTarget_coversBothAxes() {
        int[] dims = ThumbnailHelper.aspectFillDimensions(300, 300, 4000, 2250);
        assertEquals(533, dims[0]);
        assertEquals(300, dims[1]);
        assertTrue(dims[0] >= 300);
        assertTrue(dims[1] >= 300);
    }

    @Test
    public void aspectFillDimensions_portrait9x16_coversSquareTarget() {
        int[] dims = ThumbnailHelper.aspectFillDimensions(300, 300, 1080, 1920);
        assertEquals(300, dims[0]);
        assertEquals(533, dims[1]);
        assertTrue(dims[0] >= 300);
        assertTrue(dims[1] >= 300);
    }

    @Test
    public void imageDecoderTargetSize_largeSource_downsamplesToAspectFillBox() {
        int[] target = ThumbnailHelper.imageDecoderTargetSize(4000, 2250, 300, 300);
        assertEquals(533, target[0]);
        assertEquals(300, target[1]);
    }

    @Test
    public void imageDecoderTargetSize_smallSource_keepsFullSize() {
        int[] target = ThumbnailHelper.imageDecoderTargetSize(200, 150, 300, 300);
        assertEquals(200, target[0]);
        assertEquals(150, target[1]);
    }

    @Test
    public void thumbnailCacheFileName_includesVersion() {
        String name = ThumbnailHelper.thumbnailCacheFileName("abc123", 300, 300, 80);
        assertEquals("abc123_v2_300x300_q80.jpg", name);
    }
}
