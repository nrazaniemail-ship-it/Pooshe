package ir.pooshe.app;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.provider.DocumentsContract;
import android.database.Cursor;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import com.getcapacitor.*;
import com.getcapacitor.annotation.ActivityCallback;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.PluginMethod;
import androidx.activity.result.ActivityResult;

@CapacitorPlugin(name = "BackupFolder")
public class BackupFolderPlugin extends Plugin {
    private static final String PREFS = "pooshe_backup";
    private static final String KEY_TREE = "backup_tree_uri";
    private static final int FLAGS = Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION;

    @PluginMethod
    public void pickFolder(PluginCall call) {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
        intent.addFlags(FLAGS | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        startActivityForResult(call, intent, "folderPicked");
    }

    @ActivityCallback
    private void folderPicked(PluginCall call, ActivityResult result) {
        if (call == null) return;
        try {
            if (result.getResultCode() != android.app.Activity.RESULT_OK || result.getData() == null || result.getData().getData() == null) {
                call.reject("انتخاب پوشه لغو شد"); return;
            }
            Uri tree = result.getData().getData();
            int flags = result.getData().getFlags() & FLAGS;
            if ((flags & FLAGS) != FLAGS) throw new SecurityException("دسترسی خواندن و نوشتن پوشه لازم است");
            getContext().getContentResolver().takePersistableUriPermission(tree, flags);
            getContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_TREE, tree.toString()).apply();
            call.resolve(folderInfo(tree));
        } catch (Exception e) { call.reject("دسترسی به پوشه پشتیبان برقرار نشد: " + e.getMessage()); }
    }

    @PluginMethod
    public void getFolderInfo(PluginCall call) {
        String saved = getContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_TREE, "");
        if (saved.isEmpty()) { JSObject out = new JSObject(); out.put("selected", false); call.resolve(out); return; }
        try {
            Uri tree = Uri.parse(saved);
            boolean permitted = false;
            for (android.content.UriPermission p : getContext().getContentResolver().getPersistedUriPermissions()) {
                if (tree.equals(p.getUri()) && p.isReadPermission() && p.isWritePermission()) { permitted = true; break; }
            }
            if (!permitted) throw new SecurityException("permission-expired");
            call.resolve(folderInfo(tree));
        } catch (Exception e) { JSObject out = new JSObject(); out.put("selected", false); out.put("error", e.getMessage()); call.resolve(out); }
    }

    private JSObject folderInfo(Uri tree) {
        JSObject out = new JSObject(); out.put("selected", true);
        String name = "پوشه انتخاب‌شده";
        try {
            Uri doc = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree));
            try (Cursor c = getContext().getContentResolver().query(doc, new String[]{DocumentsContract.Document.COLUMN_DISPLAY_NAME}, null, null, null)) {
                if (c != null && c.moveToFirst() && c.getString(0) != null) name = c.getString(0);
            }
        } catch (Exception ignored) { }
        out.put("name", name); return out;
    }

    @PluginMethod
    public void saveBackup(PluginCall call) {
        String content = call.getString("content");
        String fileName = call.getString("fileName", "pooshe-backup.json");
        if (content == null) { call.reject("محتوای پشتیبان خالی است"); return; }
        String saved = getContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_TREE, "");
        if (saved.isEmpty()) { call.reject("ابتدا پوشه پشتیبان را انتخاب کنید"); return; }
        try {
            Uri tree = Uri.parse(saved); boolean permitted = false;
            for (android.content.UriPermission p : getContext().getContentResolver().getPersistedUriPermissions()) {
                if (tree.equals(p.getUri()) && p.isReadPermission() && p.isWritePermission()) { permitted = true; break; }
            }
            if (!permitted) throw new SecurityException("مجوز پوشه معتبر نیست؛ پوشه را دوباره انتخاب کنید");
            String treeId = DocumentsContract.getTreeDocumentId(tree);
            Uri parent = DocumentsContract.buildDocumentUriUsingTree(tree, treeId);
            Uri file = DocumentsContract.createDocument(getContext().getContentResolver(), parent, "application/json", fileName);
            if (file == null) throw new IllegalStateException("ساخت فایل پشتیبان ممکن نشد");
            try (OutputStream stream = getContext().getContentResolver().openOutputStream(file, "w")) {
                if (stream == null) throw new IllegalStateException("بازکردن فایل برای نوشتن ممکن نشد");
                stream.write(content.getBytes(StandardCharsets.UTF_8)); stream.flush();
            }
            JSObject out = new JSObject(); out.put("saved", true); out.put("fileName", fileName); out.put("folder", folderInfo(tree).getString("name")); call.resolve(out);
        } catch (Exception e) { call.reject("ذخیره نسخه پشتیبان ناموفق بود: " + e.getMessage()); }
    }
}