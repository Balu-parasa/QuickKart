# AI usage log

Tools used: Antigravity AI Coding Assistant (pair programming with Google DeepMind agentic tools)

## Significant prompts (5–10)

| # | What I asked (summary is fine) | What I did with the answer |
|---|---|---|
| 1 | Investigate QK-101 cart persistence issues across app restart and write regression tests in test-first order. | Guided the AI to verify `decrement()`, `remove()`, and `removeCoupon()` in `CartController`, ensuring tests were committed before implementing fixes. |
| 2 | Investigate QK-102 where pull-to-refresh serves stale catalog prices and cached orders. | Directed the AI to analyze `ApiClient._responseCache` and implement an explicit `refresh: true` cache bypass rather than globally disabling caching. |
| 3 | Plan and implement Part B offline cart reconciliation and safe idempotent checkout. | Adopted the strategy to reconcile before order placement, auto-accept price drops, require review for price increases/stock drops, and enforce UUID v4 idempotency keys with single-retry timeouts. |
| 4 | Design regression test suite for Part C remote configuration, update policy, and server-driven home layouts. | Validated that tests covered bare `ProviderContainer` reactivity, offline cache fallback under `'config.v1'`, numeric version comparison edge cases, and malformed home layout inputs. |
| 5 | Review Part C implementation for race conditions, error handling, and update button actions. | Intercepted multiple implementation flaws regarding URL launching, asynchronous update race conditions, and UI state resets. |
| 6 | Refine optional update dialog error persistence and out-of-order remote config updates. | Implemented a request generation counter (`_updateRequestId`) in `AppConfigController` and hoisted `dialogError` outside `StatefulBuilder`. |

## When the AI was wrong or misleading (at least 3)

### 1.
- **What it suggested:**
  The AI attempted to implement external URL launching in `home_screen.dart` using Flutter's `SystemNavigator.routeInformationUpdated(uri: uri)`.
- **Why it was wrong:**
  `SystemNavigator.routeInformationUpdated` is designed exclusively for updating browser history state in Flutter Web applications. It does nothing on Android or iOS and completely fails to launch external URLs in the system web browser.
- **How I noticed:**
  Inspected the diff of `home_screen.dart` during code review and checked Flutter's official API documentation for `SystemNavigator`.
- **What I did instead:**
  Added the standard `url_launcher: ^6.3.1` dependency to `pubspec.yaml` and implemented `launchUrl(uri, mode: LaunchMode.externalApplication)` with strict URI host and HTTP/HTTPS scheme validation.

### 2.
- **What it suggested:**
  The AI placed the error state variable (`String? dialogError`) inside the builder callback of `StatefulBuilder` in the optional update dialog:
  ```dart
  showDialog(
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        String? dialogError;
        ...
  ```
- **Why it was wrong:**
  Declaring `dialogError` inside the builder function causes it to be re-initialized to `null` every time `setDialogState()` triggers a rebuild, instantly erasing the error message from the screen as soon as it is set.
- **How I noticed:**
  Noticed during the Phase 2 code review of `home_screen.dart` by tracing state lifecycle during UI rebuilds.
- **What I did instead:**
  Hoisted `dialogError` outside the `StatefulBuilder` closure so its state persists across rebuilds when `setDialogState()` is invoked.

### 3.
- **What it suggested:**
  In `AppConfigController`, when handling live configuration stream updates (`remoteUpdates.listen`), the AI directly invoked `_load()` asynchronously without concurrency control:
  ```dart
  _sub = _repo.remoteUpdates.listen((_) async {
    state = await _repo.load();
  });
  ```
- **Why it was wrong:**
  If multiple remote update events arrive in quick succession (or if a network hiccup delays an earlier fetch), an earlier slow HTTP response could complete *after* a later response, overwriting fresh configuration with stale data.
- **How I noticed:**
  Identified during the Part C architectural review while verifying bare `ProviderContainer` live stream safety.
- **What I did instead:**
  Introduced a request generation counter (`_updateRequestId`). Each reload increments the counter, and the result is applied only if the returned generation matches the latest request ID.

## What I would NOT trust an AI with in this codebase, and why

1. **Verification of Test Execution and Pass Status:**
   - In environments where runtime SDKs (such as the Flutter SDK on this Windows host) are not installed or executable from the shell, AI models frequently hallucinate or assert that "all unit tests passed successfully." I would not trust an AI to verify runtime correctness without actual, logged execution outputs.
2. **Subtle Business Rule Boundaries and Contract Constraints:**
   - Pure coding models often make unprompted changes to utility functions (e.g. rewriting `formatMoney` or changing `payable > threshold` in `CartPricing`) or modify restricted backend/mock server files to make tests pass conveniently, which violates public contracts or architectural restrictions.
3. **Flutter Widget State Lifecycle and Rebuild Scopes:**
   - AIs frequently make subtle scoping mistakes with Flutter state management (such as declaring state variables inside builder callbacks or using non-functional platform navigation APIs for external intents). Every widget interaction and state transition must be verified against actual Flutter framework mechanics.
