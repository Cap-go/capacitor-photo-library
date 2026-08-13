package app.capgo.plugin.photo_library;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class PhotoLibraryServiceTest {

    @Test
    public void librarySortOrder_doesNotUseSqlLimitOrOffset() {
        String sortOrder = PhotoLibraryService.librarySortOrder();

        assertFalse(sortOrder.toUpperCase().contains("LIMIT"));
        assertFalse(sortOrder.toUpperCase().contains("OFFSET"));
        assertTrue(sortOrder.contains("date_added"));
        assertTrue(sortOrder.contains("DESC"));
    }
}
