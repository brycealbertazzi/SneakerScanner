# ML Kit text recognition — optional language models not used by this app
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# GoMarketMe affiliate SDK — vendored closed-source core jar with no consumer
# rules of its own. Keep it whole so release minification can't strip the
# attribution paths (a failure that would only ever show up in production).
-keep class co.gomarketme.** { *; }
-dontwarn co.gomarketme.**

# RevenueCat's purchases-android keeps an unused buildQueryPurchaseHistoryParams helper that
# references QueryPurchaseHistoryParams, removed in Play Billing 9. Nothing calls it — the live
# path (QueryPurchaseHistoryUseCase) only reads BillingResult — so it is safe to shrink away.
-dontwarn com.android.billingclient.api.QueryPurchaseHistoryParams
-dontwarn com.android.billingclient.api.QueryPurchaseHistoryParams$Builder
