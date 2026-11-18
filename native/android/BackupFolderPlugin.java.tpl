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
import android.print.PrintManager;
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
            // Scan the shared MediaStore.Files index, not only Downloads. Some Android
            // builds do not immediately expose app-created Downloads rows in that collection;
            // missing a duplicate makes MediaStore append "(1)" AFTER the extension.
            Uri files = MediaStore.Files.getContentUri("external");
            String[] projection = {
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.RELATIVE_PATH
            };
            try (android.database.Cursor cursor = getContext().getContentResolver().query(
                    files, projection, null, null, null)) {
                if (cursor == null) throw new IllegalStateException("بررسی نام فایل‌های موجود ممکن نشد");
                int nameColumn = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME);
                int pathColumn = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH);
                String wantedPath = RELATIVE_DIR.replaceAll("^/+|/+$", "");
                while (cursor.moveToNext()) {
                    String existingName = nameColumn >= 0 ? cursor.getString(nameColumn) : null;
                    String existingPath = pathColumn >= 0 ? cursor.getString(pathColumn) : null;
                    String normalizedPath = existingPath == null ? "" : existingPath.replaceAll("^/+|/+$", "");
                    if (wantedPath.equalsIgnoreCase(normalizedPath)
                            && fileName.equalsIgnoreCase(existingName == null ? "" : existingName.trim())) {
                        return true;
                    }
                }
                return false;
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

    // Keep the print WebView alive while Android's print UI is visible.
    private WebView printWebView;

    @PluginMethod
    public void savePdf(PluginCall call) {
        String html = call.getString("html");
        String requestedName = call.getString("fileName", "pooshe-report.pdf");
        if (html == null || html.trim().isEmpty()) {
            call.reject("محتوای گزارش برای چاپ خالی است");
            return;
        }

        final String fileName;
        try {
            fileName = uniqueFileName(requestedName);
            final android.app.Activity activity = getActivity();
            if (activity == null) throw new IllegalStateException("صفحه فعال برنامه در دسترس نیست");

            activity.runOnUiThread(() -> {
                final WebView webView = new WebView(activity);
                final Handler handler = new Handler(Looper.getMainLooper());
                final java.util.concurrent.atomic.AtomicBoolean finished = new java.util.concurrent.atomic.AtomicBoolean(false);
                printWebView = webView;

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

                Runnable timeout = () -> {
                    if (finished.compareAndSet(false, true)) {
                        cleanupPdfView(webView);
                        if (printWebView == webView) printWebView = null;
                        call.reject("آماده‌سازی پنجره چاپ بیش از ۴۵ ثانیه طول کشید");
                    }
                };
                handler.postDelayed(timeout, 45000);

                webView.setWebViewClient(new WebViewClient() {
                    @Override public void onPageFinished(WebView view, String url) {
                        if (finished.get()) return;
                        handler.postDelayed(() -> {
                            if (finished.get()) return;
                            try {
                                android.print.PrintManager manager =
                                    (android.print.PrintManager) activity.getSystemService(android.content.Context.PRINT_SERVICE);
                                if (manager == null) throw new IllegalStateException("سرویس چاپ اندروید در دسترس نیست");

                                String jobName = fileName.replaceFirst("(?i)\\.pdf$", "");
                                PrintDocumentAdapter adapter = view.createPrintDocumentAdapter(jobName);
                                PrintAttributes attributes = new PrintAttributes.Builder()
                                    .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
                                    .setResolution(new PrintAttributes.Resolution("pooshe", "Pooshe", 300, 300))
                                    .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                                    .setColorMode(PrintAttributes.COLOR_MODE_COLOR)
                                    .build();

                                manager.print("پوشه - " + jobName, adapter, attributes);
                                finished.set(true);
                                handler.removeCallbacks(timeout);

                                JSObject result = new JSObject();
                                result.put("saved", false);
                                result.put("printDialogOpened", true);
                                result.put("fileName", fileName);
                                result.put("folder", "انتخاب محل ذخیره در پنجره چاپ اندروید");
                                call.resolve(result);

                                handler.postDelayed(() -> {
                                    cleanupPdfView(view);
                                    if (printWebView == view) printWebView = null;
                                }, 300000);
                            } catch (Exception e) {
                                if (finished.compareAndSet(false, true)) {
                                    handler.removeCallbacks(timeout);
                                    cleanupPdfView(view);
                                    if (printWebView == view) printWebView = null;
                                    call.reject("بازکردن پنجره چاپ اندروید ناموفق بود: " + e.getMessage(), e);
                                }
                            }
                        }, 900);
                    }

                    @Override public void onReceivedError(WebView view, android.webkit.WebResourceRequest request, android.webkit.WebResourceError error) {
                        if (request != null && request.isForMainFrame() && finished.compareAndSet(false, true)) {
                            handler.removeCallbacks(timeout);
                            cleanupPdfView(view);
                            if (printWebView == view) printWebView = null;
                            call.reject("بارگذاری گزارش برای چاپ ناموفق بود");
                        }
                    }
                });

                String printableHtml = html.replace("</head>",
                    "<style>html,body{background:#fff!important}.report-actions,.report-preview-toolbar,.judicial-actions,.form-actions,button{display:none!important}body{margin:24px}</style></head>");
                webView.loadDataWithBaseURL("https://localhost/", printableHtml, "text/html", "UTF-8", null);
            });
        } catch (Exception e) {
            call.reject("آماده‌سازی PDF ناموفق بود: " + e.getMessage(), e);
        }
    }

}
