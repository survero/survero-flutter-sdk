## 0.4.1

* Fix: a second `show`/trigger while a survey sheet is open (reason `busy`) no longer releases the gate held by the
  first one, so a third call can no longer slip through while the sheet is still on screen.

## 0.4.0

* **Surveys v2:** `Survero.surveys.show(slug)` and automatic display when a tracked event is a survey trigger
  (needs `Survero.surveys.attach(navigatorKey)`). Both go through the server gate (audience rules, caps, already
  answered) plus local caps (1 impression / 7 days, 2 dismissals, answered).
* `SurveySheet` paints `single_choice`, `emoji`, `star`, `nps` and `free_text`, with the follow-up in the same
  sheet, server style + `SurveroTheme` + app theme, RTL, 44 pt targets and WCAG AA text contrast.
* Headless mode: `Survero.surveys.renderer(...)`. Kill switch: `Survero.surveys.enabled(false)`.
* Events: `$survey_gate_evaluated` (always, with reason), `$survey_shown`, `$survey_answered`, `$survey_dismissed`.
* Responses and impressions are retried if offline.
* `Survero.show(context:, surveyId:)` is deprecated.

## 0.3.0

* **Events:** `Survero.track`, `screen`, `flush`; automatic `$install`, `$session_started` and `$session_ended`
  (30-minute inactivity); persistent `device_id`; context (platform, app version, locale, country) stamped on
  every event. Batches of up to 100, sent every 15 s, at 20 queued events and when the app goes to background.
* **Identity:** `Survero.identify`, `reset`, `setTraits` / `setTrait`. Retried if offline.
* **Bridges:** `Survero.addSink` (forward events to other tools) and `SurveroSink` (plug Survero into an existing
  analytics service).
* **Debug builds don't send events** unless `enableInDebug: true`.
* Offline queues capped at 100 items and purged after 7 days; responses retried with the same `Idempotency-Key`.
* Survey config cache with a 1-hour TTL and ETag revalidation; `clearCache()` now works.
* Web-safe device locale.

## 0.2.0

* **Breaking (server side):** the SDK must be initialized with the project **public key** (`pk_live_…`).
  Secret keys (`sk_…`) are rejected by `/sdk/*` routes, and `Survero.init` warns if one is passed.
* Responses are sent with the API's snake_case contract (`survey_id`, `device_os`, `app_version`…).
  Earlier versions sent camelCase; the API keeps accepting it.
* Tests for the show → submit flow (config fetch with cache, submit, offline queue and flush).

## 0.1.0

* Star rating survey modal, config cache and offline queue.
