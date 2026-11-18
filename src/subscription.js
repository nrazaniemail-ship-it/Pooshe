/**
 * Subscription entitlement for Pooshe. Local-first mode intentionally documents its
 * device-local limitations; Bazaar purchases are queried natively through Poolakey.
 */
export const BAZAAR_RSA_PUBLIC_KEY = import.meta.env?.VITE_BAZAAR_RSA_PUBLIC_KEY || "";
export const PRODUCTS = Object.freeze([
 {id:"trial_subscription",title:"اشتراک آزمایشی",durationDays:7,priceRial:0,label:"رایگان · ۷ روز"},
 {id:"pooshe_pro_yearly",title:"اشتراک یک‌ساله پوشه پرو",durationDays:365,priceRial:9000000,label:"۹٬۰۰۰٬۰۰۰ ریال · یک‌ساله"},
 {id:"pooshe_pro_6_months",title:"اشتراک شش‌ماهه پوشه پرو",durationDays:180,priceRial:6000000,label:"۶٬۰۰۰٬۰۰۰ ریال · شش‌ماهه"},
 {id:"pooshe_pro_3_months",title:"اشتراک سه‌ماهه پوشه پرو",durationDays:90,priceRial:3000000,label:"۳٬۰۰۰٬۰۰۰ ریال · سه‌ماهه"},
 {id:"pooshe_pro_monthly",title:"اشتراک ماهانه پوشه پرو",durationDays:30,priceRial:1500000,label:"۱٬۵۰۰٬۰۰۰ ریال · ماهانه"}
]);
const STORAGE_KEY="pooshe.subscription.v1",TRIAL_MS=7*24*60*60*1000;
const PAID_IDS=new Set(PRODUCTS.filter(p=>p.id!=="trial_subscription").map(p=>p.id));
export class SubscriptionAccess {
 constructor({isNative=()=>false,billing=null}={}){this.isNative=isNative;this.billing=billing;this.connected=false;this.lastError="";this.state=this.loadState();}
 loadState(){try{const s=JSON.parse(localStorage.getItem(STORAGE_KEY)||"null");if(s&&s.version===1&&Number(s.trialStartedAt)>0)return s;}catch{}const now=Date.now(),s={version:1,trialStartedAt:now,lastSeenAt:now,subscriptions:[],trialPurchase:false,checkedAt:0};try{localStorage.setItem(STORAGE_KEY,JSON.stringify(s))}catch{}return s;}
 saveState(){try{localStorage.setItem(STORAGE_KEY,JSON.stringify(this.state))}catch(e){console.warn("Subscription state persistence failed",e)}}
 now(){const n=Math.max(Date.now(),Number(this.state.lastSeenAt)||0);this.state.lastSeenAt=n;this.saveState();return n;}
 activePaid(){const now=this.now();return (this.state.subscriptions||[]).some(x=>PAID_IDS.has(x.productId)&&(!x.expiresAt||Number(x.expiresAt)>now));}
 snapshot(){const now=this.now(),paid=this.activePaid(),trialPurchase=!!this.state.trialPurchase,localTrial=now-Number(this.state.trialStartedAt)<TRIAL_MS;const trial=trialPurchase||(!paid&&localTrial);return {mode:paid||trial?"full":"read-only",paid,trial,daysLeft:trial?Math.max(0,Math.ceil((Number(this.state.trialStartedAt)+TRIAL_MS-now)/86400000)):0,billingConnected:this.connected,billingConfigured:!!BAZAAR_RSA_PUBLIC_KEY};}
 canWrite(){return this.snapshot().mode==="full";}
 async initialize(){if(!this.isNative()||!this.billing||!BAZAAR_RSA_PUBLIC_KEY)return this.snapshot();try{const r=await this.billing.connect({rsaPublicKey:BAZAAR_RSA_PUBLIC_KEY});this.connected=!!r?.connected;if(this.connected)await this.refresh();}catch(e){this.lastError=e?.message||String(e);console.warn("Cafe Bazaar connection failed",e)}return this.snapshot();}
 async refresh(){if(!this.isNative()||!this.billing||!this.connected)return this.snapshot();try{const r=await this.billing.getSubscribedProducts(),list=Array.isArray(r?.subscriptions)?r.subscriptions:[];this.state.subscriptions=list.filter(x=>x&&typeof x.productId==="string").map(x=>({productId:x.productId,purchaseToken:x.purchaseToken||"",orderId:x.orderId||"",purchaseTime:Number(x.purchaseTime)||0,payload:x.payload||"",dataSignature:x.dataSignature||""}));this.state.trialPurchase=list.some(x=>x?.productId==="trial_subscription");this.state.checkedAt=this.now();this.saveState();this.lastError="";}catch(e){this.lastError=e?.message||String(e)}return this.snapshot();}
 async purchase(productId){if(!PRODUCTS.some(p=>p.id===productId))throw new Error("شناسه محصول اشتراک معتبر نیست.");if(!this.isNative())throw new Error("خرید اشتراک فقط در نسخه اندروید و از طریق کافه‌بازار ممکن است.");if(!this.connected)await this.initialize();if(!this.connected)throw new Error(this.lastError||"کلید عمومی RSA کافه‌بازار تنظیم نشده یا اتصال بازار برقرار نیست.");const result=await this.billing.subscribeProduct({productId,payload:"pooshe-pro-v1"});if(!result?.purchaseToken)throw new Error("بازار تأیید خرید معتبر برنگرداند.");await this.refresh();if(productId==="trial_subscription"&&!this.state.trialPurchase)throw new Error("بازار اشتراک آزمایشی را فعال اعلام نکرد.");if(PAID_IDS.has(productId)&&!this.activePaid())throw new Error("خرید دریافت شد اما اشتراک فعال از بازار بازیابی نشد.");return this.snapshot();}
}
