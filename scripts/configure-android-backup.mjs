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

const iconSource=path.resolve("resources/icon.png");
if(!fs.existsSync(iconSource))throw new Error("Pooshe launcher icon resource is missing");
const res=path.join(root,"app/src/main/res");
const iconBytes=fs.readFileSync(iconSource);
for(const density of ["mipmap-mdpi","mipmap-hdpi","mipmap-xhdpi","mipmap-xxhdpi","mipmap-xxxhdpi"]){
  const dir=path.join(res,density);fs.mkdirSync(dir,{recursive:true});
  fs.writeFileSync(path.join(dir,"ic_launcher.png"),iconBytes);
  fs.writeFileSync(path.join(dir,"ic_launcher_round.png"),iconBytes);
}
const drawable=path.join(res,"drawable-nodpi");fs.mkdirSync(drawable,{recursive:true});
fs.writeFileSync(path.join(drawable,"pooshe_icon.png"),iconBytes);
const adaptive=path.join(res,"mipmap-anydpi-v26");fs.mkdirSync(adaptive,{recursive:true});
const xml='<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/pooshe_icon_background"/><foreground android:drawable="@drawable/pooshe_icon"/></adaptive-icon>';
fs.writeFileSync(path.join(adaptive,"ic_launcher.xml"),xml);
fs.writeFileSync(path.join(adaptive,"ic_launcher_round.xml"),xml);
const values=path.join(res,"values");fs.mkdirSync(values,{recursive:true});
const colorFile=path.join(values,"pooshe_icon_colors.xml");
fs.writeFileSync(colorFile,'<resources><color name="pooshe_icon_background">#FFFFFF</color></resources>');
console.log("Configured Pooshe launcher icons for web and Android");
