# Survero Flutter SDK

Product events, user identity and in-app surveys for Flutter.

- **Events:** `track`, `screen`, automatic `$install` / `$session_started` / `$session_ended`.
- **Identity:** a persistent device id, `identify(userId)` after login, `setTraits` for user properties.
- **Surveys:** a survey configured in the dashboard is shown as a bottom sheet and the answer is sent.

Everything is queued on disk when offline and retried. Nothing throws into your UI.

## Install

```yaml
dependencies:
  survero: ^0.4.1
```

Or let your agent do it: `npx survero init` in the app folder adds the package, writes `Survero.init` in
`lib/main.dart` and tells you the one manual step (the navigator key for surveys).

## Keys

Create a **public key** (`pk_live_…`) in the dashboard (Settings → API Keys) and use it in the app.
Public keys can only fetch surveys and send responses, so it is fine if someone extracts one from the app.

**Never ship a secret key (`sk_live_…`) in an app.** The API rejects them on SDK routes and `Survero.init`
prints a warning.

## `Survero.init` options

| Option | Default | |
|---|---|---|
| `apiKey` | — | Project **public** key (`pk_…`). |
| `appVersion` | — | Your app version (e.g. from `package_info_plus`): slice results by release. |
| `userId` | — | Same as calling `identify` right after init. |
| `enableInDebug` | `false` | Debug builds send nothing unless `true`. To test without committing it: `enableInDebug: const bool.fromEnvironment('SURVERO_DEBUG')` and `flutter run --dart-define=SURVERO_DEBUG=true`. |
| `flushInterval` | 15 s | Events are batched; `await Survero.flush()` sends them now (useful in tests). |
| `baseUrl` | Survero cloud | Self-hosting or a staging API (`…/api/v1`). |

Reserved prop keys are dropped with a warning (they are columns): `platform`, `app_version`, `sdk_version`,
`country`, `country_ip`, `locale`, `user_id`, `device_id`, `session_id`, `source`, `environment`, `event_id`,
`event_name`, `client_ts`, `server_ts`, `project_id`, `identity`.

## Usage

```dart
await Survero.init(
  apiKey: 'pk_live_xxxxxxxx',
  appVersion: '2.4.0', // stamped on every event and response
);

// Events: snake_case names (≤ 40 chars). Booleans are sent as 0/1.
Survero.track('story_completed', {'story_id': 'abc', 'duration': 42});
Survero.screen('paywall');

// After login / logout. Survero links the device to the user; events from before the login
// are attributed to the user too (nothing is rewritten).
Survero.identify('user-123');
Survero.setTraits({'plan': 'premium', 'motivation': 'travel'});
Survero.reset();

// Forward every event to another tool (e.g. Firebase Analytics):
Survero.addSink((event) => FirebaseAnalytics.instance.logEvent(name: event.name));

```

## Surveys

Surveys are configured in the dashboard (type, question per language, trigger event, audience rules, caps). The SDK
paints the sheet: your app has no survey widget.

```dart
final navigatorKey = GlobalKey<NavigatorState>();
// MaterialApp(navigatorKey: navigatorKey, …)
Survero.surveys.attach(navigatorKey);

// Automatic: if a survey has trigger_event = story_completed and this user is eligible, it opens by itself.
Survero.track('story_completed');

// Manual, by slug. It goes through the same gate: audience rules, caps, already answered.
final outcome = await Survero.surveys.show('sean-ellis', context: context);
```

- **Types:** `single_choice`, `emoji`, `star`, `nps`, `free_text`. One sheet, one tap; an optional follow-up
  question appears in the same sheet.
- **Language:** the server sends the copy already in the device language (fallback: same language → project
  default → English → first available). Right-to-left languages are laid out RTL.
- **Caps:** at most one survey impression every 7 days per device, never again after answering or after two
  dismissals. The server applies its own caps and rules too.
- **Every evaluation is tracked** as `$survey_gate_evaluated` with a `reason` (`shown`, `not_eligible`,
  `cooldown`, `answered`, `dismissed_max`, `no_context`, `offline`…), so "why didn't the survey show?" has an answer.
  Also `$survey_shown`, `$survey_answered`, `$survey_dismissed`.
- **Style:** server style (dashboard) → `Survero.surveys.theme(SurveroTheme(...))` → your app theme
  (light/dark, typography).
  The primary color paints the selected answer and the buttons; the rest of the sheet follows the app theme.
- **Navigation:** the sheet is a route on the attached navigator. Track the trigger event after your own navigation
  settles (e.g. after `Navigator.pop`): a `pop` that runs once the sheet is open closes the sheet, not your screen.
- **Your own UI (headless):** `Survero.surveys.renderer((context, survey) async => SurveyOutcome.answered(...))`.
  The SDK still records impressions, caps and events.
- **Kill switch:** `Survero.surveys.enabled(false)`.

`Survero.show(context:, surveyId:)` (star surveys by id) still works for apps on 0.1–0.3 and is deprecated.

The SDK never throws into your UI: if the survey can't be loaded or sent, it logs with `debugPrint` and returns.

### Already have an analytics service?

Plug Survero into it instead of changing every call:

```dart
const survero = SurveroSink(deny: {'debug_tap'});

void log(String name, Map<String, Object?> params) {
  firebase.logEvent(name: name, parameters: params);
  survero.log(name, params);
}
```

### Debug builds

In debug builds events are **not sent** (only logged and passed to sinks) so QA reinstalls don't pollute your
data. Use `Survero.init(..., enableInDebug: true)` to send them. Surveys always work.

### Sessions

A session ends after 30 minutes without activity. `$session_ended` (with `duration_s`) is sent when the next
session starts, because mobile apps can't reliably report when they are killed.

## Local development

Point the SDK at a local API with `baseUrl: 'http://localhost:4000/api/v1'` (Android emulator:
`http://10.0.2.2:4000/api/v1`). See `example/`.
