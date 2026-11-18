package __PACKAGE__

import androidx.activity.ComponentActivity
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import ir.cafebazaar.poolakey.Payment
import ir.cafebazaar.poolakey.Connection
import ir.cafebazaar.poolakey.config.PaymentConfiguration
import ir.cafebazaar.poolakey.config.SecurityCheck
import ir.cafebazaar.poolakey.request.PurchaseRequest

@CapacitorPlugin(name = "CafeBazaarBilling")
class CafeBazaarBillingPlugin : Plugin() {
    companion object {
        private val ALLOWED_PRODUCT_IDS = setOf(
            "trial_subscription",
            "pooshe_pro_monthly",
            "pooshe_pro_3_months",
            "pooshe_pro_6_months",
            "pooshe_pro_yearly"
        )
    }
    @Volatile private var payment: Payment? = null
    @Volatile private var connection: Connection? = null
    @Volatile private var connected = false
    @Volatile private var connecting = false

    @PluginMethod
    fun connect(call: PluginCall) {
        val key = call.getString("rsaPublicKey")?.trim().orEmpty()
        if (key.isEmpty()) {
            call.reject("کلید عمومی پرداخت کافه‌بازار تنظیم نشده است.")
            return
        }
        if (connected && payment != null) {
            call.resolve(JSObject().put("connected", true))
            return
        }
        if (connecting) {
            call.reject("اتصال به سرویس پرداخت در حال انجام است؛ دوباره تلاش کنید.")
            return
        }
        val config = PaymentConfiguration(localSecurityCheck = SecurityCheck.Enable(rsaPublicKey = key))
        val p = Payment(context = context.applicationContext, config = config)
        payment = p
        connecting = true
        connection = p.connect {
            connectionSucceed {
                connected = true
                connecting = false
                call.resolve(JSObject().put("connected", true))
            }
            connectionFailed { error ->
                connected = false
                connecting = false
                call.reject("اتصال به کافه‌بازار ناموفق بود: ${error.message ?: "خطای نامشخص"}")
            }
            disconnected {
                connected = false
                connecting = false
            }
        }
    }

    @PluginMethod
    fun subscribeProduct(call: PluginCall) {
        val productId = call.getString("productId")?.trim().orEmpty()
        if (productId.isEmpty()) { call.reject("شناسه اشتراک مشخص نشده است."); return }
        if (productId !in ALLOWED_PRODUCT_IDS) {
            call.reject("شناسه محصول در فهرست رسمی اشتراک‌های Pooshe نیست.")
            return
        }
        val p = payment
        if (!connected || p == null) { call.reject("ابتدا به سرویس پرداخت کافه‌بازار متصل شوید."); return }
        val host = bridge.activity as? ComponentActivity
        if (host == null) { call.reject("صفحه پرداخت در این محیط در دسترس نیست."); return }
        val payload = call.getString("payload") ?: "pooshe-pro-v1"
        val request = PurchaseRequest(productId = productId, payload = payload, dynamicPriceToken = null)
        p.subscribeProduct(host.activityResultRegistry, request) {
            purchaseFlowBegan { }
            failedToBeginFlow { error -> call.reject("باز کردن صفحه پرداخت ناموفق بود: ${error.message ?: "خطای نامشخص"}") }
            purchaseSucceed { info ->
                call.resolve(JSObject()
                    .put("productId", info.productId)
                    .put("purchaseToken", info.purchaseToken)
                    .put("orderId", info.orderId)
                    .put("purchaseTime", info.purchaseTime)
                    .put("payload", info.payload)
                    .put("dataSignature", info.dataSignature))
            }
            purchaseCanceled { call.reject("پرداخت توسط کاربر لغو شد.") }
            purchaseFailed { error -> call.reject("خرید اشتراک ناموفق بود: ${error.message ?: "خطای نامشخص"}") }
        }
    }

    @PluginMethod
    fun getSubscribedProducts(call: PluginCall) {
        val p = payment
        if (!connected || p == null) { call.reject("ابتدا به سرویس پرداخت کافه‌بازار متصل شوید."); return }
        p.getSubscribedProducts {
            querySucceed { list ->
                val arr = JSArray()
                list.forEach { item ->
                    arr.put(JSObject()
                        .put("productId", item.productId)
                        .put("purchaseToken", item.purchaseToken)
                        .put("orderId", item.orderId)
                        .put("purchaseTime", item.purchaseTime)
                        .put("payload", item.payload)
                        .put("dataSignature", item.dataSignature))
                }
                call.resolve(JSObject().put("subscriptions", arr))
            }
            queryFailed { error -> call.reject("بررسی اشتراک‌های فعال ناموفق بود: ${error.message ?: "خطای نامشخص"}") }
        }
    }

    @PluginMethod
    fun getSubscriptionSkuDetails(call: PluginCall) {
        val productId = call.getString("productId")?.trim().orEmpty()
        val p = payment
        if (productId.isEmpty()) { call.reject("شناسه اشتراک مشخص نشده است."); return }
        if (productId !in ALLOWED_PRODUCT_IDS) {
            call.reject("شناسه محصول در فهرست رسمی اشتراک‌های Pooshe نیست.")
            return
        }
        if (!connected || p == null) { call.reject("ابتدا به سرویس پرداخت کافه‌بازار متصل شوید."); return }
        p.getSubscriptionSkuDetails(listOf(productId)) {
            getSkuDetailsSucceed { list ->
                val arr = JSArray()
                list.forEach { item ->
                    arr.put(JSObject().put("sku", item.sku).put("type", item.type).put("price", item.price).put("title", item.title).put("description", item.description))
                }
                call.resolve(JSObject().put("products", arr))
            }
            getSkuDetailsFailed { error -> call.reject("دریافت مشخصات اشتراک ناموفق بود: ${error.message ?: "خطای نامشخص"}") }
        }
    }

    @PluginMethod
    fun disconnect(call: PluginCall) {
        try { connection?.disconnect() } catch (_: Throwable) { }
        connection = null
        payment = null
        connected = false
        connecting = false
        call.resolve(JSObject().put("connected", false))
    }
}
