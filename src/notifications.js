import {Capacitor} from "@capacitor/core";
import {LocalNotifications} from "@capacitor/local-notifications";
const hash=s=>{let h=0;for(let i=0;i<s.length;i++)h=(h*31+s.charCodeAt(i))|0;return Math.abs(h)||1};
const eventDates=s=>[["شروع مرحله: "+(s.title||"بدون عنوان"),"startDate"],["موعد پایان مرحله: "+(s.title||"بدون عنوان"),"dueDate"],[s.eventTitle||"رویداد پرونده","eventDate"]].filter(x=>s[x[1]]).map(x=>({title:x[0],date:s[x[1]],kind:x[1]}));
export async function scheduleCaseReminders(cases,settings){
 if(!Capacitor.isNativePlatform())return;
 try{
  const pending=(await LocalNotifications.getPending()).notifications;
  if(pending.length)await LocalNotifications.cancel({notifications:pending.map(n=>({id:n.id}))});
  if(!settings.notify)return;
  const p=await LocalNotifications.checkPermissions();if(p.display!=="granted")return;
  const soundEnabled=settings.reminderSound!==false;
  let channelId="pooshe-reminders-silent";
  try{channelId=soundEnabled?"pooshe-reminders-sound":"pooshe-reminders-silent";await LocalNotifications.createChannel({id:channelId,name:"یادآورهای پوشه",description:"اعلان رویدادهای پرونده‌ها",importance:5,sound:soundEnabled?"default":null,vibration:true,visibility:1});}catch(e){console.warn("ساخت کانال اعلان ممکن نشد",e)}
  const list=[];
  for(const c of cases)for(const s of c.steps||[]){
   if(s.status==="done")continue;
   for(const ev of eventDates(s)){
    if(ev.kind==="eventDate"&&s.eventReminderEnabled===false)continue;
    const at=new Date(ev.date+"T"+(settings.reminderTime||"09:00")+":00");
    at.setMinutes(at.getMinutes()-Number(settings.reminderMinutes||0));
    if(at>Date.now())list.push({id:hash(c.id+s.id+ev.kind),title:"یادآور رویداد پرونده",body:ev.title+" | پرونده: "+(c.title||"بدون عنوان")+" | موکل: "+(c.client||"نام موکل ثبت نشده"),schedule:{at},channelId,sound:soundEnabled?"default":null,extra:{caseId:c.id,stepId:s.id,event:ev.kind}});
   }
  }
  if(list.length)await LocalNotifications.schedule({notifications:list.slice(0,60)});
 }catch(e){console.warn("زمان‌بندی اعلان بومی انجام نشد",e)}
}
export async function askReminderPermission(){
 if(Capacitor.isNativePlatform())return (await LocalNotifications.requestPermissions()).display==="granted";
 if(!("Notification"in window))return false;return (await Notification.requestPermission())==="granted";
}
export function checkWebReminders(cases,settings){
 if(!settings.notify||!("Notification"in window)||Notification.permission!=="granted")return;
 const now=new Date();
 for(const c of cases)for(const s of c.steps||[]){
  if(s.status==="done")continue;
  for(const ev of eventDates(s)){
   if(ev.kind==="eventDate"&&s.eventReminderEnabled===false)continue;
   const at=new Date(ev.date+"T"+(settings.reminderTime||"09:00")+":00");
   at.setMinutes(at.getMinutes()-Number(settings.reminderMinutes||0));
   const key="pooshe-web-"+c.id+"-"+s.id+"-"+ev.kind+"-"+ev.date;
   if(now>=at&&now<new Date(at.getTime()+86400000)&&!sessionStorage.getItem(key)){
    new Notification("یادآور رویداد پرونده",{body:ev.title+" | پرونده: "+(c.title||"بدون عنوان")+" | موکل: "+(c.client||"نام موکل ثبت نشده")});
    sessionStorage.setItem(key,"1");
   }
  }
 }
}