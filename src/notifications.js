import {Capacitor} from "@capacitor/core";
import {LocalNotifications} from "@capacitor/local-notifications";
const hash=s=>{let h=0;for(let i=0;i<s.length;i++)h=(h*31+s.charCodeAt(i))|0;return Math.abs(h)||1};
export async function scheduleCaseReminders(cases,settings){
 if(!settings.notify||!Capacitor.isNativePlatform())return;
 try{
  const p=await LocalNotifications.checkPermissions();if(p.display!=="granted")return;
  const pending=(await LocalNotifications.getPending()).notifications;
  if(pending.length)await LocalNotifications.cancel({notifications:pending.map(n=>({id:n.id}))});
  const list=[];
  for(const c of cases)for(const s of c.steps||[]){
   if(!s.dueDate||s.status==="done")continue;
   const at=new Date(s.dueDate+"T"+(settings.reminderTime||"09:00")+":00");
   at.setMinutes(at.getMinutes()-Number(settings.reminderMinutes||0));
   if(at>Date.now())list.push({id:hash(c.id+s.id),title:"یادآوری پرونده: "+c.title,body:s.title+" | موعد: "+s.dueDate,schedule:{at},extra:{caseId:c.id,stepId:s.id}});
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
  if(!s.dueDate||s.status==="done")continue;
  const at=new Date(s.dueDate+"T"+(settings.reminderTime||"09:00")+":00");
  at.setMinutes(at.getMinutes()-Number(settings.reminderMinutes||0));
  const key="pooshe-web-"+c.id+"-"+s.id+"-"+s.dueDate;
  if(now>=at&&now<new Date(at.getTime()+86400000)&&!sessionStorage.getItem(key)){
   new Notification("یادآوری پرونده: "+c.title,{body:s.title+" | موعد: "+s.dueDate});
   sessionStorage.setItem(key,"1");
  }
 }
}