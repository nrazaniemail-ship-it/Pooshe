import fs from "node:fs";
import path from "node:path";
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
