# Decisions & trade-offs

> Short and specific beats long and generic. Bullet points are fine.

## 1. Cart reconciliation policy (Feature 1)

- **When does reconciliation run, and why there?**
  - Reconciliation runs inside `CheckoutController.placeOrder()` immediately before submitting the order payload to `/v1/orders`.
  - It also re-runs if the backend returns a transient or validation mismatch error (such as `PRICE_CHANGED`, `INSUFFICIENT_STOCK`, `PRODUCT_UNAVAILABLE`, `QUANTITY_LIMIT`, `COUPON_INVALID`, `TOTAL_MISMATCH`).
  - *Why there:* Reconciling at the point of checkout prevents race conditions where prices or stock change between cart viewing and checkout, guaranteeing that the customer only pays amounts they agreed to per `BUSINESS_RULES.md §5`.
- **What does the user see for each kind of change?** (price up / down, out of stock, quantity reduced, discontinued, coupon removed)
  - **Price down:** Silently applied without asking the user. The cart is updated with the lower price and the order continues uninterrupted.
  - **Price up:** Halts checkout and returns `CheckoutNeedsReview` with `PriceChanged`. The user sees the old and new prices and must confirm before proceeding.
  - **Out of stock:** Halts checkout and returns `CheckoutNeedsReview` with `OutOfStock`. The line is removed from the cart.
  - **Quantity reduced:** Halts checkout and returns `CheckoutNeedsReview` with `QuantityReduced`. The line quantity is capped to `min(stock, maxPerOrder)`.
  - **Discontinued (missing product ID):** Halts checkout and returns `CheckoutNeedsReview` with `ProductUnavailable`. The line is removed from the cart.
  - **Coupon removed:** If a coupon is expired or unknown, halts checkout and returns `CheckoutNeedsReview` with `CouponRemoved`. (Note: if cart value drops below `minOrderPaise`, the coupon remains attached per `BUSINESS_RULES.md §3` but gives ₹0 discount).
- **What happens to out-of-stock / discontinued items?**
  - They are immediately stripped from the reconciled cart and discarded from local storage so that unavailable products are never submitted to the backend.
- **Offline-built carts:**
  - Carts can be assembled completely offline using locally cached catalog data. When the network reconnects and checkout is triggered, `CartReconciler.reconcile()` validates every line against the server via `catalogApi.getProductsByIds()` and `couponApi.validateCoupon()`. If prices or availability differ, the user must review before placing the order.
- **Alternatives considered and rejected:**
  - *Reconciling on every app foreground or catalog screen view:* Rejected because frequent bulk API calls drain battery and data on poor connections, and transient price changes during casual browsing disrupt the user experience before purchase intent is finalized.

## 2. Safe checkout & idempotency

- **How are duplicate orders prevented?** (key generation, lifetime, storage)
  - **In-flight guard:** `CheckoutController` tracks `state.isPlacingOrder`. Any concurrent or double-tap requests while an order is in progress are immediately rejected with `CheckoutFailure('Order is already in progress, please wait...')`.
  - **UUID v4 Idempotency-Key:** Generated via `Uuid().v4()` before sending the POST request and passed as the `Idempotency-Key` HTTP header.
  - **Lifetime:** Stored in memory as `_activeIdempotencyKey` on the controller for the duration of the checkout attempt and its immediate automatic retry. It is reset to null only when checkout completes successfully (`CheckoutSuccess`) or when the cart requires user review (`CheckoutNeedsReview`).
- **What does the user see on timeout / lost response?**
  - On the first `ApiTimeoutException`, `CheckoutController` automatically retries the request exactly once using the *same* `Idempotency-Key`.
  - If the retry also times out, checkout halts with `CheckoutFailure('The request timed out. Your order may have been placed. Please check "My orders" before trying again.', canRetry: true)`.
  - The cart is deliberately NOT cleared so items are not lost if the order did not reach the server.
- **Edge cases you handled:**
  - Double-tap and concurrent button presses blocked via boolean state guard.
  - Server-side store closure (`STORE_CLOSED`) handled with user-friendly error message.
  - Stale pricing/stock race condition handled by catching server 4xx codes and automatically running re-reconciliation.
  - Transient network drops handled with honest error messages and `canRetry: true`.
- **Edge cases you know you did NOT handle:**
  - Persisting the active in-flight idempotency key across full OS process kills during the 5-second HTTP timeout window.
  - Automated background polling of `/v1/orders` to auto-resolve pending timeouts before prompting the user.

## 3. Remote config, updates & kill switch (Feature 2)

- **Caching strategy and failure behaviour:**
  - Successfully fetched configuration from `GET /v1/config` is persisted as JSON under the key `'config.v1'` in `KeyValueStore`.
  - When offline or when the server returns an error or malformed payload, `ConfigRepository` falls back to the cached `'config.v1'` JSON.
  - If the cache is missing or corrupt, it safely falls back to `AppConfig.defaults()`. Remote config loading never crashes the app.
- **How live updates propagate, and how you avoid leaks:**
  - `AppConfigController` subscribes to `ConfigRepository.remoteUpdates` during `build()`.
  - To prevent memory leaks, the `StreamSubscription` is cancelled in `ref.onDispose()`.
  - To prevent out-of-order asynchronous races where an older slow network response overwrites newer published configuration, a monotonic request generation counter (`_updateRequestId`) is incremented on every reload.
- **Force / optional update UX:**
  - Evaluated via `UpdatePolicy.evaluate(currentVersion: appVersion, minSupportedVersion: config.minSupportedVersion, latestVersion: config.latestVersion)`.
  - **Required update:** Renders a full-screen blocking `_ForceUpdateScreen`. All back navigation, gestures, and tab switches are blocked. Tapping "Update now" opens `config.updateUrl` via `url_launcher` (`LaunchMode.externalApplication`). If URL launching fails, an honest error message is displayed on screen without unblocking the user.
  - **Optional update:** Displays a non-blocking modal dialog. The user can dismiss it ("Later") or tap "Update now". If URL launching fails, an error message appears inside the dialog without dismissing it. Once dismissed, it will not re-prompt during the session for the same latest version.
- **Store closed UX:**
  - When `config.storeOpen == false`, a persistent banner (`_StoreClosedBanner`) appears at the top of the home screen displaying `config.storeClosedMessage`.
  - Browsing catalog products and adding items to the cart remain completely functional.
  - Checkout is disabled in `CheckoutController` and the cart checkout button, displaying an honest explanation instead of failing silently.
- **Server-driven home: robustness to bad config:**
  - `HomeLayout.parse()` handles null, empty, malformed JSON, unknown section IDs, and duplicates.
  - Valid recognized section IDs (`banner`, `categories`, `deals`, `all_products`) are preserved in order and deduplicated.
  - If the layout JSON is completely invalid or produces no valid sections, it safely falls back to `defaultSections`.

## 4. Feature 3 (if attempted)

- *Not attempted.* Focused on delivering comprehensive, robust, and verified solutions for Parts A, B, and C with full test-first coverage and architecture contract compliance.

## 5. Other decisions

- Packages added (and why):
  - `url_launcher: ^6.3.1`: Required in Part C to launch external URLs in the platform browser when users tap "Update now" on the forced or optional update screens.
- Refactors you made to the existing code (and why):
  - Added optional `refresh: true` parameter to `ApiClient.get()`, `CatalogApi.getPage()`, and `CatalogRepository.getPage()` to allow user-initiated pull-to-refresh actions to bypass the 5-minute in-memory response cache (QK-102).
  - Added `_updateRequestId` generation counter in `AppConfigController` to prevent stale out-of-order network responses from clobbering newer live configuration pushes.

## 6. Looking ahead

- What would you do with one more week?
  - Implement full offline SQLite/Drift persistence for catalog pages and search indexing.
  - Build Part D (Live order tracking with SSE/WebSocket order status updates and interactive timeline).
  - Add comprehensive Golden widget regression tests for the server-driven layout configurations and force update modal states.
- What breaks first at 10× users (10k DAU)? What would you change?
  - The single-endpoint batch reconciliation (`/v1/products?ids=...`) would experience load spikes. I would introduce server-side HTTP caching headers (ETag / `If-None-Match`) and CDN edge caching for product catalog queries, as well as Redis-backed distributed locks for inventory reservations during checkout.
- How would you ship a hotfix for a critical bug without a store release?
  - Use the remote configuration system: set `store_open: false` with a custom maintenance message to halt broken checkout paths, or use `home_sections` and remote config flags to hide affected modules/promotions until an updated build or backend patch is deployed.
