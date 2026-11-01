# Survero Flutter SDK

Product events, user identity and in-app surveys for Flutter.

- **Events:** `track`, `screen`, automatic `$install` / `$session_started` / `$session_ended`.
- **Identity:** a persistent device id, `identify(userId)` after login, `setTraits` for user properties.
- **Surveys:** a survey configured in the dashboard is shown as a bottom sheet and the answer is sent.

Everything is queued on disk when offline and retried. Nothing throws into your UI.

## Install

```yaml
dependencies:
  survero: ^0.2.0
```

## Keys

Create a **public key** (`pk_live_…`) in the dashboard (Settings → API Keys) and use it in the app.
Public keys can only fetch surveys and send responses, so it is fine if someone extracts one from the app.

**Never ship a secret key (`sk_live_…`) in an app.** The API rejects them on SDK routes and `Survero.init`
prints a warning.

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

// Anywhere with a BuildContext:
await Survero.show(
  context: context,
  surveyId: '8b0f3c1e-…', // survey id from the dashboard
  onComplete: (response) => debugPrint('rating ${response.rating}'),
  onDismiss: () => debugPrint('dismissed'),
);
```

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
