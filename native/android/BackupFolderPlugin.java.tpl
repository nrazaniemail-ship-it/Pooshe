package ir.pooshe.app;

import android.content.ContentValues;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintDocumentInfo;
import android.print.PageRange;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.graphics.Color;
import android.graphics.pdf.PdfDocument;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import com.getcapacitor.*;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.OutputStream;
import java.io.FileInputStream;
import java.nio.charset.StandardCharsets;

@CapacitorPlugin(name = "BackupFolder")
public class BackupFolderPlugin extends Plugin {
    private static final String RELATIVE_DIR = Environment.DIRECTORY_DOWNLOADS + "/pooshe backups/";

    private String uniqueFileName(String requested) throws Exception {
        String clean = new File(requested == null ? "pooshe-export" : requested).getName().trim();
        // Repair legacy names such as report.xls (1) to report (1).xls.
        java.util.regex.Matcher misplaced = java.util.regex.Pattern
            .compile("^(.*?)(\\.[A-Za-z0-9]{1,8})\\s*\\((\\d+)\\)$")
            .matcher(clean);
        if (misplaced.matches()) clean = misplaced.group(1) + " (" + misplaced.group(3) + ")" + misplaced.group(2);

        int dot = clean.lastIndexOf('.');
        String base = dot > 0 && dot < clean.length() - 1 ? clean.substring(0, dot) : clean;
        String ext = dot > 0 && dot < clean.length() - 1 ? clean.substring(dot) : "";
        String candidate = clean;
        int index = 1;
        while (fileNameExists(candidate)) {
            candidate = base + " (" + index++ + ")" + ext;
        }
        return candidate;
    }

    private boolean fileNameExists(String fileName) throws Exception {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Query the exact collection used by saveBytes(), with an exact display-name match.
            // Never silently fall through when the provider cannot perform the check: MediaStore
            // may otherwise rename a duplicate to "report.xls (1)" after the extension.
            try (android.database.Cursor cursor = getContext().getContentResolver().query(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    new String[] { MediaStore.MediaColumns._ID },
                    MediaStore.MediaColumns.DISPLAY_NAME + " = ?",
                    new String[] { fileName },
                    null)) {
                if (cursor == null) throw new IllegalStateException("بررسی نام فایل در پوشه دانلود ممکن نشد");
                return cursor.moveToFirst();
            }
        }
        File dir = new File(getContext().getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "pooshe backups");
        return new File(dir, fileName).exists();
    }

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
            fileName = uniqueFileName(fileName);
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

    private void cleanupPdfView(WebView view) {
        try {
            if (view != null) {
                if (view.getParent() instanceof android.view.ViewGroup) {
                    ((android.view.ViewGroup) view.getParent()).removeView(view);
                }
                view.stopLoading();
                view.destroy();
            }
        } catch (Exception ignored) { }
    }

    @PluginMethod
    public void savePdf(PluginCall call) {
        String html = call.getString("html");
        String requestedName = call.getString("fileName", "pooshe-report.pdf");
        if (html == null || html.trim().isEmpty()) {
            call.reject("محتوای گزارش برای PDF خالی است");
            return;
        }
        final String fileName;
        try {
            ensureFolder();
            fileName = uniqueFileName(requestedName);
            final android.app.Activity activity = getActivity();
            if (activity == null) throw new IllegalStateException("صفحه فعال برنامه در دسترس نیست");
            activity.runOnUiThread(() -> {
                final WebView webView = new WebView(activity);
                final Handler handler = new Handler(Looper.getMainLooper());
                final java.util.concurrent.atomic.AtomicBoolean finished = new java.util.concurrent.atomic.AtomicBoolean(false);
                final File tempPdf;
                try {
                    tempPdf = File.createTempFile("pooshe-print-", ".pdf", getContext().getCacheDir());
                } catch (Exception e) {
                    call.reject("ساخت فایل موقت PDF ناموفق بود: " + e.getMessage(), e);
                    return;
                }
                final Runnable cleanup = () -> {
                    cleanupPdfView(webView);
                    if (tempPdf.exists()) tempPdf.delete();
                };
                final Runnable timeout = () -> {
                    if (finished.compareAndSet(false, true)) {
                        cleanup.run();
                        call.reject("تولید PDF بیش از ۶۰ ثانیه طول کشید");
                    }
                };
                FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
                );
                activity.addContentView(webView, params);
                webView.setAlpha(0.01f);
                webView.setClickable(false);
                webView.setFocusable(false);
                webView.setBackgroundColor(Color.WHITE);
                webView.getSettings().setJavaScriptEnabled(true);
                webView.getSettings().setDefaultTextEncodingName("UTF-8");
                webView.setWebViewClient(new WebViewClient() {
                    @Override public void onPageFinished(WebView view, String url) {
                        if (finished.get()) return;
                        handler.postDelayed(() -> {
                            if (finished.get()) return;
                            try {
                                PrintAttributes attributes = new PrintAttributes.Builder()
                                    .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
                                    .setResolution(new PrintAttributes.Resolution("pooshe", "Pooshe PDF", 300, 300))
                                    .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                                    .setColorMode(PrintAttributes.COLOR_MODE_COLOR)
                                    .build();
                                PrintDocumentAdapter adapter = view.createPrintDocumentAdapter("Pooshe Report");
                                adapter.onLayout(null, attributes, new CancellationSignal(),
                                    new PrintDocumentAdapter.LayoutResultCallback() {
                                        @Override public void onLayoutFinished(PrintDocumentInfo info, boolean changed) {
                                            if (finished.get()) return;
                                            try {
                                                final ParcelFileDescriptor descriptor = ParcelFileDescriptor.open(
                                                    tempPdf,
                                                    ParcelFileDescriptor.MODE_CREATE |
                                                    ParcelFileDescriptor.MODE_TRUNCATE |
                                                    ParcelFileDescriptor.MODE_READ_WRITE
                                                );
                                                adapter.onWrite(new PageRange[] { PageRange.ALL_PAGES }, descriptor,
                                                    new CancellationSignal(),
                                                    new PrintDocumentAdapter.WriteResultCallback() {
                                                        @Override public void onWriteFinished(PageRange[] pages) {
                                                            try {
                                                                descriptor.close();
                                                                ByteArrayOutputStream output = new ByteArrayOutputStream();
                                                                try (FileInputStream input = new FileInputStream(tempPdf)) {
                                                                    byte[] buffer = new byte[8192];
                                                                    int count;
                                                                    while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
                                                                }
                                                                byte[] pdfBytes = output.toByteArray();
                                                                if (pdfBytes.length < 500) throw new IllegalStateException("محتوای PDF خالی است");
                                                                saveBytes(fileName, "application/pdf", pdfBytes);
                                                                if (finished.compareAndSet(false, true)) {
                                                                    handler.removeCallbacks(timeout);
                                                                    cleanup.run();
                                                                    JSObject result = new JSObject();
                                                                    result.put("saved", true);
                                                                    result.put("fileName", fileName);
                                                                    result.put("folder", "Download/pooshe backups");
                                                                    call.resolve(result);
                                                                }
                                                            } catch (Exception ex) {
                                                                if (finished.compareAndSet(false, true)) {
                                                                    handler.removeCallbacks(timeout);
                                                                    cleanup.run();
                                                                    call.reject("ذخیره PDF ناموفق بود: " + ex.getMessage(), ex);
                                                                }
                                                            }
                                                        }
                                                        @Override public void onWriteFailed(CharSequence error) {
                                                            if (finished.compareAndSet(false, true)) {
                                                                handler.removeCallbacks(timeout);
                                                                try { descriptor.close(); } catch (Exception ignored) { }
                                                                cleanup.run();
                                                                call.reject("تبدیل گزارش به PDF ناموفق بود: " + error);
                                                            }
                                                        }
                                                        @Override public void onWriteCancelled() {
                                                            if (finished.compareAndSet(false, true)) {
                                                                handler.removeCallbacks(timeout);
                                                                try { descriptor.close(); } catch (Exception ignored) { }
                                                                cleanup.run();
                                                                call.reject("ساخت PDF لغو شد");
                                                            }
                                                        }
                                                    });
                                            } catch (Exception ex) {
                                                if (finished.compareAndSet(false, true)) {
                                                    handler.removeCallbacks(timeout);
                                                    cleanup.run();
                                                    call.reject("شروع تبدیل PDF ناموفق بود: " + ex.getMessage(), ex);
                                                }
                                            }
                                        }
                                        @Override public void onLayoutFailed(CharSequence error) {
                                            if (finished.compareAndSet(false, true)) {
                                                handler.removeCallbacks(timeout);
                                                cleanup.run();
                                                call.reject("صفحه‌بندی گزارش PDF ناموفق بود: " + error);
                                            }
                                        }
                                        @Override public void onLayoutCancelled() {
                                            if (finished.compareAndSet(false, true)) {
                                                handler.removeCallbacks(timeout);
                                                cleanup.run();
                                                call.reject("صفحه‌بندی PDF لغو شد");
                                            }
                                        }
                                    }, null);
                            } catch (Exception ex) {
                                if (finished.compareAndSet(false, true)) {
                                    handler.removeCallbacks(timeout);
                                    cleanup.run();
                                    call.reject("آماده‌سازی PDF ناموفق بود: " + ex.getMessage(), ex);
                                }
                            }
                        }, 800);
                    }
                    @Override public void onReceivedError(WebView view, android.webkit.WebResourceRequest request, android.webkit.WebResourceError error) {
                        if (request != null && request.isForMainFrame() && finished.compareAndSet(false, true)) {
                            handler.removeCallbacks(timeout);
                            cleanup.run();
                            call.reject("بارگذاری محتوای گزارش برای PDF ناموفق بود");
                        }
                    }
                });
                handler.postDelayed(timeout, 60000);
                String printableHtml = html.replace("</head>",
                    "<style>html,body{background:#fff!important}body{margin:24px;-webkit-print-color-adjust:exact;print-color-adjust:exact}.report-actions,.report-preview-toolbar,.judicial-actions,.form-actions,button{display:none!important}</style></head>");
                webView.loadDataWithBaseURL("https://localhost/", printableHtml, "text/html", "UTF-8", null);
            });
        } catch (Exception e) {
            call.reject("آماده‌سازی PDF ناموفق بود: " + e.getMessage(), e);
        }
    }

}
