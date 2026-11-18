import { Capacitor, registerPlugin } from "@capacitor/core";
import { BAZAAR_RSA_PUBLIC_KEY } from "./bazaar-config.js";
import { evaluateAccess } from "./access-policy.js";

const Billing = registerPlugin("CafeBazaarBilling");
export const PRODUCTS = [
  { id: "trial_subscription", title: "اشتراک آزمایشی", duration: "۷ روز", price: "رایگان", trial: true },
  { id: "pooshe_pro_yearly", title: "اشتراک یک‌ساله پوشه پرو", duration: "۳۶۵ روز", price: "۹٬۰۰۰٬۰۰۰ ریال" },
  { id: "pooshe_pro_6_months", title: "اشتراک شش‌ماهه پوشه پرو", duration: "۱۸۰ روز", price: "۶٬۰۰۰٬۰۰۰ ریال" },
  { id: "pooshe_pro_3_months", title: "اشتراک سه‌ماهه پوشه پرو", duration: "۹۰ روز", price: "۳٬۰۰۰٬۰۰۰ ریال" },
  { id: "pooshe_pro_monthly", title: "اشتراک ماهانه پوشه پرو", duration: "۳۰ روز", price: "۱٬۵۰۰٬۰۰۰ ریال" }
];
const PAID_IDS = new Set(PRODUCTS.filter(x => !x.trial).map(x => x.id));
const TRIAL_MS = 7 * 24 * 60 * 60 * 1000;
let stateRef = null, saveRef = null, onChange = () => {}, nativeReady = false;
let activeIds = new Set(), lastBillingError = "";
const now = () => Date.now();
const readTrial = () => {
  const raw = stateRef?.settings?.subscription;
  return raw && Number.isFinite(Number(raw.trialStartedAt)) ? Number(raw.trialStartedAt) : 0;
};
const localTrialActive = () => {
  const started = readTrial();
  return started > 0 && now() >= started && now() < started + TRIAL_MS;
};
export function accessStatus() {
  const evaluated = evaluateAccess({ now: now(), trialStartedAt: readTrial(), activeProductIds: [...activeIds] });
  return {
    ...evaluated,
    trialStartedAt: readTrial(),
    trialEndsAt: readTrial() ? readTrial() + TRIAL_MS : 0,
    activeProducts: [...activeIds],
    native: Capacitor.isNativePlatform(),
    configured: Boolean(BAZAAR_RSA_PUBLIC_KEY && BAZAAR_RSA_PUBLIC_KEY.trim().length > 40),
    error: lastBillingError
  };
}
async function persistTrial() { if (saveRef && stateRef) await saveRef(stateRef); }
export async function initializeAccessControl(appState, save, changed = () => {}) {
  stateRef = appState; saveRef = save; onChange = changed;
  stateRef.settings ||= {};
  const trial = stateRef.settings.subscription;
  if (!trial || !Number.isFinite(Number(trial.trialStartedAt))) {
    stateRef.settings.subscription = { trialStartedAt: now(), schema: 1 };
    await persistTrial();
  }
  if (Capacitor.isNativePlatform()) refreshSubscriptions().catch(error => {
    lastBillingError = error?.message || "بررسی اشتراک ناموفق بود"; onChange();
  });
  return accessStatus();
}
export function requireWriteAccess(action = "این عملیات") {
  if (!accessStatus().readOnly) return true;
  const message = "مهلت آزمایشی به پایان رسیده است. برای " + action +
    "، اشتراک پوشه پرو را فعال کنید. اطلاعات قبلی شما حذف نشده و همچنان قابل مشاهده و پشتیبان‌گیری است.";
  try { window.dispatchEvent(new CustomEvent("pooshe-access-denied", { detail: { message } })); } catch {}
  return false;
}
export async function refreshSubscriptions() {
  if (!Capacitor.isNativePlatform()) {
    lastBillingError = "خرید و استعلام اشتراک فقط در نسخه نصب‌شده اندروید و با کافه‌بازار انجام می‌شود.";
    return accessStatus();
  }
  if (!accessStatus().configured) {
    lastBillingError = "کلید عمومی پرداخت کافه‌بازار هنوز در src/bazaar-config.js تنظیم نشده است.";
    onChange(); return accessStatus();
  }
  try {
    await Billing.connect({ rsaPublicKey: BAZAAR_RSA_PUBLIC_KEY.trim() });
    nativeReady = true;
    const result = await Billing.getSubscribedProducts();
    const list = Array.isArray(result?.subscriptions) ? result.subscriptions : [];
    activeIds = new Set(list.map(x => x?.productId || x?.sku).filter(Boolean));
    lastBillingError = "";
  } catch (error) {
    nativeReady = false; lastBillingError = error?.message || "ارتباط با کافه‌بازار برقرار نشد.";
  }
  onChange(); return accessStatus();
}
export async function purchaseSubscription(productId) {
  if (!PAID_IDS.has(productId) && productId !== "trial_subscription") throw new Error("شناسه اشتراک نامعتبر است.");
  if (!Capacitor.isNativePlatform()) throw new Error("برای خرید، نسخه اندروید پوشه را اجرا کنید.");
  if (!accessStatus().configured) throw new Error("کلید عمومی پرداخت بازار تنظیم نشده است.");
  if (!nativeReady) { await Billing.connect({ rsaPublicKey: BAZAAR_RSA_PUBLIC_KEY.trim() }); nativeReady = true; }
  await Billing.subscribeProduct({ productId, payload: "pooshe-pro-v1" });
  await refreshSubscriptions();
  if (!activeIds.has(productId)) throw new Error("خرید ثبت شد، اما بازار هنوز اشتراک فعال را تأیید نکرده است. از گزینه بررسی اشتراک استفاده کنید.");
  return accessStatus();
}
export function subscriptionPanelMarkup() {
  const s = accessStatus();
  const remaining = s.trial && s.trialEndsAt ? Math.max(0, Math.ceil((s.trialEndsAt - now()) / 86400000)) : 0;
  const state = s.paid ? "اشتراک پولی فعال است" : s.trial ?
    (s.bazaarTrial ? "اشتراک آزمایشی بازار فعال است" : "دوره آزمایشی رایگان · " + remaining + " روز باقی‌مانده") :
    "دوره آزمایشی پایان یافته · حالت فقط مشاهده";
  const cards = PRODUCTS.filter(x => !x.trial).map(x =>
    '<article class="subscription-product"><div><b>' + x.title + '</b><small>' + x.duration + ' · ' + x.price +
    '</small></div><button class="primary" data-buy-sku="' + x.id + '">خرید اشتراک</button></article>').join("");
  return '<section class="subscription-panel"><div class="subscription-heading"><div><h3>اشتراک پوشه پرو</h3><p>وضعیت: <b>' +
    state + '</b></p></div><button class="outline" id="refreshSubscription">بررسی اشتراک</button></div>' +
    '<p class="hint">پس از پایان دوره آزمایشی، پرونده‌ها و اسناد قبلی قابل مشاهده، جست‌وجو، پشتیبان‌گیری و بازیابی می‌مانند؛ ثبت و تغییر پرونده و خروجی PDF/Excel تا فعال‌سازی اشتراک متوقف می‌شود.</p>' +
    '<div class="subscription-products">' + cards + '</div>' +
    (s.error ? '<p class="subscription-error" role="status">' + s.error + '</p>' : '') +
    (!s.native ? '<p class="hint">برای پرداخت واقعی، نسخه اندروید نصب‌شده از کافه‌بازار لازم است.</p>' : '') + '</section>';
}
export function bindSubscriptionControls() {
  document.querySelector("#refreshSubscription")?.addEventListener("click", async () => {
    const button = document.querySelector("#refreshSubscription");
    if (button) { button.disabled = true; button.textContent = "در حال بررسی…"; }
    await refreshSubscriptions();
    if (button?.isConnected) { button.disabled = false; button.textContent = "بررسی اشتراک"; }
  });
  document.querySelectorAll("[data-buy-sku]").forEach(button => button.addEventListener("click", async () => {
    const id = button.dataset.buySku, label = button.textContent;
    button.disabled = true; button.textContent = "در حال اتصال…";
    try { await purchaseSubscription(id); alert("اشتراک فعال شد. همه قابلیت‌های پوشه دوباره در دسترس است."); }
    catch (error) { alert(error?.message || "خرید اشتراک ناموفق بود."); }
    finally { if (button.isConnected) { button.disabled = false; button.textContent = label; } onChange(); }
  }));
}
