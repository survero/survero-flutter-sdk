# Survero Flutter SDK

In-app surveys for Flutter. The SDK fetches a survey configured in the Survero dashboard, shows it as a
bottom sheet and sends the answer. Answers sent offline are queued and retried on the next `init`.

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
  appVersion: '2.4.0', // optional, shown next to each response
);

// Anywhere with a BuildContext:
await Survero.show(
  context: context,
  surveyId: '8b0f3c1e-…', // survey id from the dashboard
  onComplete: (response) => debugPrint('rating ${response.rating}'),
  onDismiss: () => debugPrint('dismissed'),
);
```

The SDK never throws into your UI: if the survey can't be loaded or sent, it logs with `debugPrint` and returns.

## Local development

Point the SDK at a local API with `baseUrl: 'http://localhost:4000/api/v1'` (Android emulator:
`http://10.0.2.2:4000/api/v1`). See `example/`.
