package ir.pooshe.app;

import android.content.ContentValues;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.graphics.Color;
import android.graphics.pdf.PdfDocument;
import android.util.DisplayMetrics;
import android.view.View;
import android.webkit.WebView;
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
        WebView.enableSlowWholeDocumentDraw();
        WebView webView = new WebView(getContext());
        webView.setBackgroundColor(Color.WHITE);
        webView.getSettings().setJavaScriptEnabled(false);
        webView.setWebViewClient(new WebViewClient() {
            @Override public void onPageFinished(WebView view, String url) {
                view.post(() -> {
                    PdfDocument document = new PdfDocument();
                    try {
                        int dpi = 150;
                        int pageWidthPt = 595;
                        int pageHeightPt = 842;
                        int widthPx = Math.round(pageWidthPt * dpi / 72f);
                        int pageHeightPx = Math.round(pageHeightPt * dpi / 72f);
                        view.measure(
                            View.MeasureSpec.makeMeasureSpec(widthPx, View.MeasureSpec.EXACTLY),
                            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
                        );
                        int contentHeightPx = Math.max(Math.round(view.getContentHeight() * view.getScale()), pageHeightPx);
                        view.measure(
                            View.MeasureSpec.makeMeasureSpec(widthPx, View.MeasureSpec.EXACTLY),
                            View.MeasureSpec.makeMeasureSpec(contentHeightPx, View.MeasureSpec.EXACTLY)
                        );
                        view.layout(0, 0, widthPx, contentHeightPx);
                        view.layout(0, 0, widthPx, contentHeightPx);
                        int pageCount = Math.max(1, (int)Math.ceil(contentHeightPx / (double)pageHeightPx));
                        if (pageCount > 100) throw new IllegalStateException("تعداد صفحات PDF بیش از حد مجاز است");
                        float scale = 72f / dpi;
                        for (int pageIndex = 0; pageIndex < pageCount; pageIndex++) {
                            PdfDocument.PageInfo info = new PdfDocument.PageInfo.Builder(pageWidthPt, pageHeightPt, pageIndex + 1).create();
                            PdfDocument.Page page = document.startPage(info);
                            page.getCanvas().drawColor(Color.WHITE);
                            page.getCanvas().save();
                            page.getCanvas().scale(scale, scale);
                            page.getCanvas().translate(0, -pageIndex * pageHeightPx);
                            view.draw(page.getCanvas());
                            page.getCanvas().restore();
                            document.finishPage(page);
                        }
                        ByteArrayOutputStream output = new ByteArrayOutputStream();
                        document.writeTo(output);
                        saveBytes(fileName, "application/pdf", output.toByteArray());
                        JSObject result = new JSObject();
                        result.put("saved", true);
                        result.put("fileName", fileName);
                        result.put("folder", "Download/pooshe backups");
                        result.put("format", "A4 portrait");
                        result.put("pages", pageCount);
                        call.resolve(result);
                    } catch (Exception e) {
                        call.reject("تولید یا ذخیره PDF ناموفق بود: " + e.getMessage(), e);
                    } finally {
                        document.close();
                        view.destroy();
                    }
                });
            }
        });
        webView.loadDataWithBaseURL("https://localhost/", html, "text/html", "UTF-8", null);
    }
}
