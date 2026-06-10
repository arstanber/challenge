# Connectors setup

This app can auto-track a task's progress from external fitness data sources.

| Connector | Type | Status without setup |
|-----------|------|----------------------|
| **Apple Health** | on-device (HealthKit) | ✅ works after enabling the capability (below) |
| **Apple Fitness** | on-device (HealthKit) | ✅ same as Apple Health (Fitness data flows through HealthKit) |
| **Strava** | OAuth2 | needs app registration + secrets |
| **Google Fit** | OAuth2 | needs app registration + secrets |
| **Fitbit** | OAuth2 | needs app registration + secrets |
| **Whoop** | OAuth2 | needs app registration + secrets |
| **Garmin** | OAuth (partner-gated) | needs approved Garmin Health program |

The connector UI lives in `HabitCalendarView` (the task detail screen). All logic is in
`Challenge/Services/Connectors/`. Backend token-exchange is the `connector-oauth` Edge Function.

---

## 1. Apple Health / Apple Fitness (fully on-device — do this first)

Already wired in code. You only need to enable the capability in Xcode:

1. Open the project → target **Challenge** → **Signing & Capabilities**.
2. Click **+ Capability** → add **HealthKit**.
   - This is already declared in `Challenge/Challenge.entitlements`
     (`com.apple.developer.healthkit`) and `Info.plist`
     (`NSHealthShareUsageDescription`). Adding the capability links the framework and
     flips it on for your App ID in the developer portal.
3. Build to a **real device** (HealthKit has no data in most simulators).
4. Tap **Здоровье** or **Фитнес** on a goal's detail screen → grant permission.
   The goal's "Сегодня" ring then fills from real steps/energy/distance/exercise minutes.

Metric is inferred from the task title (`ConnectorMetric.infer`): steps / calories /
distance / exercise minutes — tweak the keyword lists there if needed.

---

## 2. OAuth providers (Strava, Google Fit, Fitbit, Whoop, Garmin)

Secrets must NOT ship in the app, so the token exchange runs in the `connector-oauth`
Edge Function. The app only carries the **public client_id**.

### 2a. Run the migration

```bash
supabase db push          # applies supabase/migrations/20260607_connector_tokens.sql
```

### 2b. Register each provider's app

For every provider you want, register a developer app and set the **redirect / callback URL** to:

```
challenge://oauth-callback
```

(Already registered in `Info.plist` under `CFBundleURLTypes` and used as
`OAuthConfig.redirectURI`.)

Where to register + scopes used in code:

| Provider | Register at | Scope in code |
|----------|-------------|---------------|
| Strava | https://www.strava.com/settings/api | `activity:read_all` |
| Google Fit |f (OAuth consent + iOS/Web client, enable **Fitness API**) | `fitness.activity.read` |
| Fitbit | https://dev.fitbit.com/apps (app type: **Personal/Client**) | `activity` |
| Whoop | https://developer.whoop.com | `read:workout read:cycles read:recovery offline` |
| Garmin | https://developer.garmin.com (Health API — partner approval required) | — |

> Google note: for the redirect to work on iOS you typically use an **iOS OAuth client**
> with a custom scheme, or a **Web client** whose redirect is `challenge://oauth-callback`.
> Pick whichever your Google project allows and put that client's id below.

### 2c. Put the public client IDs in the app

`Challenge/Services/Connectors/OAuthConnector.swift` → `enum OAuthSecrets`:

```swift
enum OAuthSecrets {
    static let strava    = "12345"                       // Strava Client ID
    static let googleFit = "xxxx.apps.googleusercontent.com"
    static let fitbit    = "23ABCD"
    static let whoop     = "uuid-client-id"
    static let garmin    = "consumer-key"
}
```

### 2d. Put the secrets in Supabase (server-side only)

```bash
supabase secrets set \
  STRAVA_CLIENT_ID=...        STRAVA_CLIENT_SECRET=... \
  GOOGLE_CLIENT_ID=...        GOOGLE_CLIENT_SECRET=... \
  FITBIT_CLIENT_ID=...        FITBIT_CLIENT_SECRET=... \
  WHOOP_CLIENT_ID=...         WHOOP_CLIENT_SECRET=... \
  GARMIN_CLIENT_ID=...        GARMIN_CLIENT_SECRET=...
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.

### 2e. Deploy the function

```bash
supabase functions deploy connector-oauth
```

### 2f. Test

Open a goal's detail → tap a provider chip → consent in the web sheet → it returns and
shows **Подключено**. The "Сегодня" ring then pulls today's value via the function.

---

## How it fits together

```
ConnectorChip (HabitCalendarView)
        │  connect()/disconnect()/todayValue()
        ▼
ConnectorService  ──►  HealthKitConnector        (Apple Health/Fitness, on-device)
        │
        └────────────►  OAuthConnector
                              │  ASWebAuthenticationSession → code
                              ▼
                        connector-oauth  (Edge Function, holds secrets + tokens)
                              │  exchange / refresh / today
                              ▼
                        connector_tokens  (RLS-locked table, service_role only)
                              │
                              ▼
                        Strava / Google Fit / Fitbit / Whoop / Garmin APIs
```

## Adding more connectors later

Suggested next ones: **Apple Watch** (already via HealthKit), **Withings**, **Oura**,
**Polar**, **Samsung Health**, **MyFitnessPal**, **Nike Run Club**.

To add an OAuth2 one: add a `case` to `DataConnector` (name/icon/tint), a `config(for:)`
entry + `OAuthSecrets` field in `OAuthConnector.swift`, and a `providerConfig` + `fetchToday`
branch in `connector-oauth/index.ts`. No UI changes needed — the chip row is data-driven.
