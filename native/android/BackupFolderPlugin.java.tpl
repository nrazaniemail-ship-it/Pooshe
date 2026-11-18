package ir.pooshe.app;

import android.content.ContentValues;
import android.content.Context;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import com.getcapacitor.*;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "BackupFolder")
public class BackupFolderPlugin extends Plugin {
    private static final String RELATIVE_DIR = Environment.DIRECTORY_DOWNLOADS + "/pooshe backups/";

    private Uri createDownload(String fileName, String mimeType, String content) throws Exception {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContentValues values = new ContentValues();
            values.put(MediaStore.MediaColumns.DISPLAY_NAME, fileName);
            values.put(MediaStore.MediaColumns.MIME_TYPE, mimeType);
            values.put(MediaStore.MediaColumns.RELATIVE_PATH, RELATIVE_DIR);
            values.put(MediaStore.MediaColumns.IS_PENDING, 1);
            Uri collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI;
            Uri uri = getContext().getContentResolver().insert(collection, values);
            if (uri == null) throw new IllegalStateException("ساخت فایل در پوشه Download ممکن نشد");
            try (OutputStream stream = getContext().getContentResolver().openOutputStream(uri, "w")) {
                if (stream == null) throw new IllegalStateException("بازکردن فایل برای نوشتن ممکن نشد");
                stream.write(content.getBytes(StandardCharsets.UTF_8));
                stream.flush();
            } catch (Exception e) {
                getContext().getContentResolver().delete(uri, null, null);
                throw e;
            }
            ContentValues done = new ContentValues();
            done.put(MediaStore.MediaColumns.IS_PENDING, 0);
            getContext().getContentResolver().update(uri, done, null, null);
            return uri;
        }
        java.io.File dir = new java.io.File(getContext().getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "pooshe backups");
        if (!dir.exists() && !dir.mkdirs()) throw new IllegalStateException("ساخت پوشه پشتیبان ممکن نشد");
        java.io.File file = new java.io.File(dir, fileName);
        try (java.io.FileOutputStream stream = new java.io.FileOutputStream(file)) {
            stream.write(content.getBytes(StandardCharsets.UTF_8));
            stream.flush();
        }
        return Uri.fromFile(file);
    }

    private void ensureFolder() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return;
        Uri marker = null;
        try {
            ContentValues values = new ContentValues();
            values.put(MediaStore.MediaColumns.DISPLAY_NAME, ".pooshe-folder-init");
            values.put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream");
            values.put(MediaStore.MediaColumns.RELATIVE_PATH, RELATIVE_DIR);
            values.put(MediaStore.MediaColumns.IS_PENDING, 1);
            marker = getContext().getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
            if (marker != null) getContext().getContentResolver().delete(marker, null, null);
        } catch (Exception e) { android.util.Log.w("Pooshe", "Could not initialize Downloads folder", e); }
    }

    @PluginMethod
    public void getFolderInfo(PluginCall call) {
        ensureFolder();
        JSObject out = new JSObject();
        out.put("selected", true);
        out.put("name", "Download/pooshe backups");
        out.put("path", "حافظه داخلی/Download/pooshe backups");
        call.resolve(out);
    }

    @PluginMethod
    public void saveFile(PluginCall call) {
        String content = call.getString("content");
        String fileName = call.getString("fileName", "pooshe-backup.json");
        String mimeType = call.getString("mimeType", "application/octet-stream");
        if (content == null) { call.reject("محتوای فایل خالی است"); return; }
        try {
            ensureFolder();
            createDownload(fileName, mimeType, content);
            JSObject out = new JSObject();
            out.put("saved", true);
            out.put("fileName", fileName);
            out.put("folder", "Download/pooshe backups");
            call.resolve(out);
        } catch (Exception e) {
            call.reject("ذخیره فایل در Download/pooshe backups ناموفق بود: " + e.getMessage(), e);
        }
    }
}