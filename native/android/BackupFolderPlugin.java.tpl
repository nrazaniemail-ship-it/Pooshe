package ir.pooshe.app;

import android.content.ContentValues;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.provider.MediaStore;
import android.print.PageRange;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintDocumentInfo;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import com.getcapacitor.*;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

@CapacitorPlugin(name = "BackupFolder")
public class BackupFolderPlugin extends Plugin {
    private static final String RELATIVE_DIR = Environment.DIRECTORY_DOWNLOADS + "/pooshe backups/";

    private Uri saveBytes(String fileName, String mimeType, byte[] bytes) throws Exception {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContentValues values = new ContentValues();
            values.put(MediaStore.MediaColumns.DISPLAY_NAME, fileName);
            values.put(MediaStore.MediaColumns.MIME_TYPE, mimeType);
            values.put(MediaStore.MediaColumns.RELATIVE_PATH, RELATIVE_DIR);
            values.put(MediaStore.MediaColumns.IS_PENDING, 1);
            Uri uri = getContext().getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
            if (uri == null) throw new IllegalStateException("ساخت فایل در پوشه Download ممکن نشد");
            try {
                try (OutputStream stream = getContext().getContentResolver().openOutputStream(uri, "w")) {
                    if (stream == null) throw new IllegalStateException("بازکردن فایل برای نوشتن ممکن نشد");
                    stream.write(bytes);
                    stream.flush();
                }
                ContentValues done = new ContentValues();
                done.put(MediaStore.MediaColumns.IS_PENDING, 0);
                getContext().getContentResolver().update(uri, done, null, null);
                return uri;
            } catch (Exception e) {
                // If the bytes were committed but finalization failed, retain the completed file.
                try (java.io.InputStream in = getContext().getContentResolver().openInputStream(uri)) {
                    if (in != null && in.read() >= 0) {
                        ContentValues done = new ContentValues();
                        done.put(MediaStore.MediaColumns.IS_PENDING, 0);
                        getContext().getContentResolver().update(uri, done, null, null);
                        return uri;
                    }
                } catch (Exception ignored) { }
                getContext().getContentResolver().delete(uri, null, null);
                throw e;
            }
        }
        File dir = new File(getContext().getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "pooshe backups");
        if (!dir.exists() && !dir.mkdirs()) throw new IllegalStateException("ساخت پوشه پشتیبان ممکن نشد");
        File file = new File(dir, fileName);
        try (java.io.FileOutputStream stream = new java.io.FileOutputStream(file)) {
            stream.write(bytes);
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
            saveBytes(fileName, mimeType, content.getBytes(StandardCharsets.UTF_8));
            JSObject out = new JSObject();
            out.put("saved", true);
            out.put("fileName", fileName);
            out.put("folder", "Download/pooshe backups");
            call.resolve(out);
        } catch (Exception e) {
            call.reject("ذخیره فایل در Download/pooshe backups ناموفق بود: " + e.getMessage(), e);
        }
    }

    @PluginMethod
    public void savePdf(PluginCall call) {
        String html = call.getString("html");
        String fileName = call.getString("fileName", "pooshe-report.pdf");
        if (html == null || html.trim().isEmpty()) { call.reject("محتوای چاپ خالی است"); return; }
        ensureFolder();
        WebView webView = new WebView(getContext());
        webView.getSettings().setJavaScriptEnabled(false);
        webView.setWebViewClient(new WebViewClient() {
            @Override public void onPageFinished(WebView view, String url) {
                PrintDocumentAdapter adapter = view.createPrintDocumentAdapter(fileName);
                PrintAttributes attrs = new PrintAttributes.Builder()
                    .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
                    .setResolution(new PrintAttributes.Resolution("pooshe", "Pooshe PDF", 300, 300))
                    .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                    .build();
                CancellationSignal signal = new CancellationSignal();
                adapter.onLayout(null, attrs, signal, new PrintDocumentAdapter.LayoutResultCallback() {
                    @Override public void onLayoutFinished(PrintDocumentInfo info, boolean changed) {
                        File temp = new File(getContext().getCacheDir(), "pooshe-print-" + System.currentTimeMillis() + ".pdf");
                        try {
                            ParcelFileDescriptor pfd = ParcelFileDescriptor.open(temp,
                                ParcelFileDescriptor.MODE_CREATE | ParcelFileDescriptor.MODE_TRUNCATE | ParcelFileDescriptor.MODE_READ_WRITE);
                            adapter.onWrite(new PageRange[]{PageRange.ALL_PAGES}, pfd, signal, new PrintDocumentAdapter.WriteResultCallback() {
                                @Override public void onWriteFinished(PageRange[] pages) {
                                    try {
                                        pfd.close();
                                        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                                        try (FileInputStream input = new FileInputStream(temp)) {
                                            byte[] buffer = new byte[8192]; int count;
                                            while ((count = input.read(buffer)) != -1) bytes.write(buffer, 0, count);
                                        }
                                        saveBytes(fileName, "application/pdf", bytes.toByteArray());
                                        JSObject out = new JSObject();
                                        out.put("saved", true); out.put("fileName", fileName);
                                        out.put("folder", "Download/pooshe backups"); out.put("format", "A4 portrait");
                                        call.resolve(out);
                                    } catch (Exception e) {
                                        call.reject("ذخیره PDF ناموفق بود: " + e.getMessage(), e);
                                    } finally {
                                        temp.delete(); view.destroy();
                                    }
                                }
                                @Override public void onWriteFailed(CharSequence error) {
                                    try { pfd.close(); } catch (Exception ignored) { }
                                    temp.delete(); view.destroy();
                                    call.reject("تولید PDF ناموفق بود: " + error);
                                }
                                @Override public void onWriteCancelled() {
                                    try { pfd.close(); } catch (Exception ignored) { }
                                    temp.delete(); view.destroy();
                                    call.reject("تولید PDF لغو شد");
                                }
                            });
                        } catch (Exception e) {
                            temp.delete(); view.destroy();
                            call.reject("آماده‌سازی PDF ناموفق بود: " + e.getMessage(), e);
                        }
                    }
                    @Override public void onLayoutFailed(CharSequence error) {
                        view.destroy(); call.reject("صفحه‌بندی PDF ناموفق بود: " + error);
                    }
                    @Override public void onLayoutCancelled() {
                        view.destroy(); call.reject("صفحه‌بندی PDF لغو شد");
                    }
                }, signal);
            }
        });
        webView.loadDataWithBaseURL("https://localhost/", html, "text/html", "UTF-8", null);
    }
}
