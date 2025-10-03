package app.capgo.plugin.photo_library;

import com.getcapacitor.Logger;

public class PhotoLibrary {

    public String echo(String value) {
        Logger.info("Echo", value);
        return value;
    }
}
