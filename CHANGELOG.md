## 0.2.0

* **Breaking (server side):** the SDK must be initialized with the project **public key** (`pk_live_…`).
  Secret keys (`sk_…`) are rejected by `/sdk/*` routes, and `Survero.init` warns if one is passed.
* Responses are sent with the API's snake_case contract (`survey_id`, `device_os`, `app_version`…).
  Earlier versions sent camelCase; the API keeps accepting it.
* Tests for the show → submit flow (config fetch with cache, submit, offline queue and flush).

## 0.1.0

* Star rating survey modal, config cache and offline queue.
