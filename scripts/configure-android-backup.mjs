import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
const root=path.resolve("android"),javaRoot=path.join(root,"app/src/main/java");
if(!fs.existsSync(javaRoot))throw new Error("Android project not found; run cap add android first");
function walk(dir){for(const ent of fs.readdirSync(dir,{withFileTypes:true})){const p=path.join(dir,ent.name);if(ent.isDirectory()){const found=walk(p);if(found)return found;}else if(ent.name==="MainActivity.java")return p;}return null;}
const main=walk(javaRoot);if(!main)throw new Error("MainActivity.java not found");
const source=fs.readFileSync(main,"utf8"),pkg=(source.match(/^package\s+([\w.]+);/m)||[])[1];if(!pkg)throw new Error("MainActivity package not found");
const pluginPath=path.join(path.dirname(main),"BackupFolderPlugin.java");
const plugin=fs.readFileSync("native/android/BackupFolderPlugin.java.tpl","utf8").replace(/^package ir\.pooshe\.app;/,"package "+pkg+";");
fs.writeFileSync(pluginPath,plugin);
let updated=source;
if(!updated.includes("BackupFolderPlugin.class")){
  if(!updated.includes("import com.getcapacitor.BridgeActivity;"))updated=updated.replace(/package [\w.]+;\s*/,m=>m+"\nimport com.getcapacitor.BridgeActivity;");
  if(!updated.includes("import android.os.Bundle;"))updated=updated.replace(/package [\w.]+;\s*/,m=>m+"\nimport android.os.Bundle;");
  if(/public void onCreate\(Bundle savedInstanceState\)\s*\{/.test(updated)){
    updated=updated.replace(/public void onCreate\(Bundle savedInstanceState\)\s*\{/,"public void onCreate(Bundle savedInstanceState) {\n        registerPlugin(BackupFolderPlugin.class);");
  } else {
    updated=updated.replace(/}\s*$/, "\n    @Override\n    public void onCreate(Bundle savedInstanceState) {\n        registerPlugin(BackupFolderPlugin.class);\n        super.onCreate(savedInstanceState);\n    }\n}\n");
  }
  fs.writeFileSync(main,updated);
}
console.log("Configured persistent SAF backup folder picker for "+pkg);
// Native Android PDF printing uses the same MainActivity JavaScript bridge pattern
// as Namello 1.0.2. This is intentionally independent from BackupFolderPlugin/Excel.
if(!updated.includes("PoosheAndroid")){
  const printImports = [
    "import android.content.Context;",
    "import android.os.Handler;",
    "import android.os.Looper;",
    "import android.print.PrintAttributes;",
    "import android.print.PrintDocumentAdapter;",
    "import android.print.PrintManager;",
    "import android.webkit.JavascriptInterface;",
    "import android.webkit.WebView;",
    "import android.webkit.WebViewClient;"
  ].join("\n");
  updated=updated.replace(/^(package [\w.]+;)/m, "$1\n"+printImports);
  const onCreateAnchor="super.onCreate(savedInstanceState);";
  if(!updated.includes(onCreateAnchor)) throw new Error("MainActivity onCreate anchor missing for PoosheAndroid bridge");
  updated=updated.replace(onCreateAnchor, onCreateAnchor+"\n        WebView bridgeWebView = getBridge() != null ? getBridge().getWebView() : null;\n        if (bridgeWebView != null) bridgeWebView.addJavascriptInterface(new PoosheAndroid(), \"PoosheAndroid\");");
  const nativeClass = [
    "    private WebView pooshePrintWebView;",
    "",
    "    private final class PoosheAndroid {",
    "        @JavascriptInterface",
    "        public boolean setLauncherIconColor(final String color) {",
    "            String key = \"Black\";",
    "            if (\"#d6b36b\".equalsIgnoreCase(color)) key = \"Gold\";",
    "            else if (\"#56c4b6\".equalsIgnoreCase(color)) key = \"Teal\";",
    "            else if (\"#82aeea\".equalsIgnoreCase(color)) key = \"Blue\";",
    "            else if (\"#e49baa\".equalsIgnoreCase(color)) key = \"Rose\";",
    "            else if (\"#9b7bea\".equalsIgnoreCase(color)) key = \"Purple\";",
    "            else if (\"#58a66b\".equalsIgnoreCase(color)) key = \"Green\";",
    "            else if (\"#ed9148\".equalsIgnoreCase(color)) key = \"Orange\";",
    "            else if (\"#e5c84b\".equalsIgnoreCase(color)) key = \"Yellow\";",
    "            else if (!\"black\".equalsIgnoreCase(color)) return false;",
    "            android.content.pm.PackageManager pm = getPackageManager();",
    "            String[] keys = {\"Black\",\"Gold\",\"Teal\",\"Blue\",\"Rose\",\"Purple\",\"Green\",\"Orange\",\"Yellow\"};",
    "            for (String item : keys) {",
    "                android.content.ComponentName component = new android.content.ComponentName(MainActivity.this, getPackageName()+\".MainActivityIcon\"+item);",
    "                pm.setComponentEnabledSetting(component, item.equals(key) ? android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED : android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED, android.content.pm.PackageManager.DONT_KILL_APP);",
    "            }",
    "            return true;",
    "        }",
    "",
    "        @JavascriptInterface",
    "        public boolean printHtml(final String html, final String requestedName) {",
    "            if (html == null || html.trim().isEmpty()) return false;",
    "            final String jobName = (requestedName == null || requestedName.trim().isEmpty()) ? \"pooshe-report\" : requestedName.trim();",
    "            runOnUiThread(() -> {",
    "                try {",
    "                    final WebView printView = new WebView(MainActivity.this);",
    "                    pooshePrintWebView = printView;",
    "                    printView.setBackgroundColor(android.graphics.Color.WHITE);",
    "                    printView.getSettings().setJavaScriptEnabled(true);",
    "                    printView.getSettings().setDefaultTextEncodingName(\"UTF-8\");",
    "                    printView.setWebViewClient(new WebViewClient() {",
    "                        private boolean started = false;",
    "                        @Override",
    "                        public void onPageFinished(final WebView view, String url) {",
    "                            if (started) return;",
    "                            started = true;",
    "                            new Handler(Looper.getMainLooper()).postDelayed(() -> {",
    "                                try {",
    "                                    PrintManager manager = (PrintManager) getSystemService(Context.PRINT_SERVICE);",
    "                                    if (manager == null) throw new IllegalStateException(\"Android PrintManager unavailable\");",
    "                                    PrintDocumentAdapter adapter = view.createPrintDocumentAdapter(jobName);",
    "                                    PrintAttributes attributes = new PrintAttributes.Builder()",
    "                                        .setMediaSize(PrintAttributes.MediaSize.ISO_A4)",
    "                                        .setMinMargins(PrintAttributes.Margins.NO_MARGINS)",
    "                                        .build();",
    "                                    manager.print(jobName, adapter, attributes);",
    "                                } catch (Throwable error) {",
    "                                    android.util.Log.e(\"PooshePDF\", \"Could not open Android print dialog\", error);",
    "                                    runOnUiThread(() -> android.widget.Toast.makeText(MainActivity.this,",
    "                                        \"باز کردن پنجره چاپ ناموفق بود\", android.widget.Toast.LENGTH_LONG).show());",
    "                                }",
    "                            }, 900);",
    "                        }",
    "                    });",
    "                    printView.loadDataWithBaseURL(\"https://localhost/\", html, \"text/html\", \"UTF-8\", null);",
    "                } catch (Throwable error) {",
    "                    android.util.Log.e(\"PooshePDF\", \"PDF preparation failed\", error);",
    "                    android.widget.Toast.makeText(MainActivity.this,",
    "                        \"آماده‌سازی PDF ناموفق بود\", android.widget.Toast.LENGTH_LONG).show();",
    "                }",
    "            });",
    "            return true;",
    "        }",
    "    }"
  ].join("\n");
  updated=updated.replace(/\n}\s*$/, "\n"+nativeClass+"\n}\n");
}

// Persist MainActivity after both plugin registration and JavaScript bridge injection.
// Previously the file was written before PoosheAndroid was added, so the APK never received the bridge.
fs.writeFileSync(main,updated);

const iconSource=path.resolve("resources/icon.png");
if(!fs.existsSync(iconSource))throw new Error("Pooshe launcher icon resource is missing");
const res=path.join(root,"app/src/main/res"),drawable=path.join(res,"drawable-nodpi");
fs.mkdirSync(drawable,{recursive:true});
const colors=[["Black","#000000"],["Gold","#d6b36b"],["Teal","#56c4b6"],["Blue","#82aeea"],["Rose","#e49baa"],["Purple","#9b7bea"],["Green","#58a66b"],["Orange","#ed9148"],["Yellow","#e5c84b"]];
const py=String.raw`from PIL import Image
import sys, os
src,out=sys.argv[1],sys.argv[2]
original=Image.open(src).convert("RGBA")
palette=[("black","#000000"),("gold","#d6b36b"),("teal","#56c4b6"),("blue","#82aeea"),("rose","#e49baa"),("purple","#9b7bea"),("green","#58a66b"),("orange","#ed9148"),("yellow","#e5c84b")]
for name,color in palette:
 im=original.copy(); pix=im.load(); rgb=tuple(int(color[i:i+2],16) for i in (1,3,5))
 for y in range(im.height):
  for x in range(im.width):
   r,g,b,a=pix[x,y]
   if not a: continue
   lum=.2126*r+.7152*g+.0722*b
   if lum>=245: continue
   strength=(245-lum)/245
   pix[x,y]=(round(255*(1-strength)+rgb[0]*strength),round(255*(1-strength)+rgb[1]*strength),round(255*(1-strength)+rgb[2]*strength),a)
 im.save(os.path.join(out,"pooshe_icon_"+name+".png"))
`;
const pyRun=spawnSync("python3",["-c",py,iconSource,drawable],{encoding:"utf8"});
if(pyRun.status!==0)throw new Error("Launcher icon generation failed: "+(pyRun.stderr||"Install Pillow before Android configure"));
const densities=["mipmap-mdpi","mipmap-hdpi","mipmap-xhdpi","mipmap-xxhdpi","mipmap-xxxhdpi"],adaptive=path.join(res,"mipmap-anydpi-v26");
fs.mkdirSync(adaptive,{recursive:true});
for(const [key] of colors){
 const id=key.toLowerCase(),png=path.join(drawable,"pooshe_icon_"+id+".png");
 for(const density of densities){const dir=path.join(res,density);fs.mkdirSync(dir,{recursive:true});fs.copyFileSync(png,path.join(dir,"ic_launcher_"+id+".png"));if(id==="black"){fs.copyFileSync(png,path.join(dir,"ic_launcher.png"));fs.copyFileSync(png,path.join(dir,"ic_launcher_round.png"));}}
 const xml='<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/pooshe_icon_background"/><foreground android:drawable="@drawable/pooshe_icon_'+id+'"/></adaptive-icon>';
 fs.writeFileSync(path.join(adaptive,"ic_launcher_"+id+".xml"),xml);
 if(id==="black"){fs.writeFileSync(path.join(adaptive,"ic_launcher.xml"),xml);fs.writeFileSync(path.join(adaptive,"ic_launcher_round.xml"),xml);}
}
const values=path.join(res,"values");fs.mkdirSync(values,{recursive:true});
fs.writeFileSync(path.join(values,"pooshe_icon_colors.xml"),'<resources><color name="pooshe_icon_background">#FFFFFF</color></resources>');
const manifestPath=path.join(root,"app/src/main/AndroidManifest.xml");
let manifest=fs.readFileSync(manifestPath,"utf8");
const activityRe=/<activity\\b[^>]*android:name=["'](?:\\.|[\\w.])*MainActivity["'][^>]*>[\\s\\S]*?<\\/activity>/;
const activity=manifest.match(activityRe);
if(!activity)throw new Error("MainActivity declaration not found in AndroidManifest.xml");
const activityXml=activity[0].replace(/<intent-filter>[\\s\\S]*?<\\/intent-filter>/g,block=>/android.intent.action.MAIN/.test(block)&&/android.intent.category.LAUNCHER/.test(block)?"":block);
if(activityXml===activity[0])throw new Error("MainActivity launcher intent filter not found");
const aliases=colors.map(([key])=>{const id=key.toLowerCase();return '<activity-alias android:name=".MainActivityIcon'+key+'" android:targetActivity=".MainActivity" android:enabled="'+(id==="black"?"true":"false")+'" android:exported="true" android:icon="@mipmap/ic_launcher_'+id+'" android:label="پوشه"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity-alias>';}).join("\\n");
manifest=manifest.replace(activity[0],activityXml+"\\n"+aliases);
fs.writeFileSync(manifestPath,manifest);
console.log("Configured selectable Pooshe Android launcher icons");
