# RevenueCat — настройка

Код уже подключён. Осталось завести проект в дашборде и подставить ключи.
Пока `Constants.RevenueCat.apiKey` = `appl_REPLACE_ME`, покупки работать не будут.

## 1. Проект и App Store Connect

1. https://app.revenuecat.com → **Create new project** → `reInspire`.
2. **Apps** → **+ New** → App Store → bundle ID приложения.
3. В App Store Connect: **Users and Access → Integrations → App Store Connect API**
   → сгенерировать **In-App Purchase key** (роль не ниже App Manager), скачать `.p8`.
   Загрузить его в RevenueCat (App settings → In-app purchase key).
   Файл положить рядом с остальными секретами: `~/Secrets/Challenge/`.
4. Там же указать **App Store Shared Secret** (ASC → App → App Information →
   Manage Shared Secret) — нужен для валидации чеков.

## 2. Продукты

**Products → Import** подтянет их из App Store Connect автоматически.
Проверить, что все семь на месте (идентификаторы из `Constants.Store`):

| Product ID | Тип |
|---|---|
| `reProMonthly` | auto-renewable |
| `reProAnnually` | auto-renewable |
| `reProLifetime` | non-renewing / non-consumable |
| `reFamilyMonthly` | auto-renewable |
| `reFamilyAnnually` | auto-renewable |
| `reMaxMonthly` | auto-renewable |
| `reMaxAnnually` | auto-renewable |

## 3. Entitlements

**Entitlements → + New**. Идентификаторы должны совпадать с
`Constants.RevenueCat` и с `ENTITLEMENT_PLANS` в вебхуке — иначе план не выдастся.

| Entitlement | Прикреплённые продукты |
|---|---|
| `premium` | `reProMonthly`, `reProAnnually`, `reProLifetime` |
| `family` | `reFamilyMonthly`, `reFamilyAnnually` |
| `max` | `reMaxMonthly`, `reMaxAnnually` |

Тиры не наследуются: `max` — отдельный entitlement, приоритет считается в коде
(`max > family > premium`), а не в RevenueCat.

## 4. Offering

**Offerings → + New** → identifier `default`, пометить **Make current**.
Добавить пакеты на все семь продуктов. Пейволл читает цены только из текущего
оффера — продукт вне оффера покупается, но без атрибуции для A/B тестов.

## 5. Ключи в приложении

**Project settings → API keys → Apple** → публичный ключ `appl_...`
→ в `reInspire/Utils/Constants.swift`:

```swift
static let apiKey = "appl_..."
```

Публичный ключ безопасно коммитить. Секретный (`sk_...`) — никогда.

## 6. Вебхук

Он источник правды для `users.plan`; клиент план в базу не пишет.

```bash
# секрет придумать любой длинный, например: openssl rand -hex 32
supabase secrets set REVENUECAT_WEBHOOK_SECRET='<секрет>'
supabase secrets set REVENUECAT_SECRET_API_KEY='sk_...'   # RC secret key

supabase functions deploy revenuecat-webhook --no-verify-jwt
```

`--no-verify-jwt` обязателен: RevenueCat не умеет выпускать Supabase JWT,
авторизация идёт по заголовку.

В RevenueCat: **Integrations → Webhooks → + New**
- URL: `https://tvuvfuguxjvzyzsjnepr.supabase.co/functions/v1/revenuecat-webhook`
- Authorization header: тот же `<секрет>`, что в `REVENUECAT_WEBHOOK_SECRET`
- Environment: Production (Sandbox отдельно, см. ниже)

Проверить кнопкой **Send test webhook** — функция вернёт
`{"ok":true,"skipped":"test_event"}`. Реальные события смотреть в
`supabase functions logs revenuecat-webhook`.

## 7. Sandbox

Песочница по умолчанию **не** выдаёт план, чтобы тестовые покупки не раздавали
подписки в проде. Для проверки на TestFlight временно:

```bash
supabase secrets set RC_ALLOW_SANDBOX=true
```

и не забыть убрать перед релизом.

## Как это работает

- `StoreService.configure()` — в `ReInspireApp.init()`, до первого экрана.
- `AuthService.loadUserProfile` → `Purchases.logIn(<supabase user id>)`.
  RevenueCat `app_user_id` == `users.id`, поэтому вебхук находит строку напрямую.
- `signOut()` → `Purchases.logOut()`, иначе следующий аккаунт на этом устройстве
  унаследует чужие entitlements.
- После покупки клиент поднимает план в памяти (мгновенный анлок UI) и
  перечитывает профиль с задержками 1/3/6 с, пока вебхук не запишет строку.
  В базу клиент не пишет — на понижение он тоже не действует, чтобы не сбить
  план, выданный сервером (члены семьи, реферальный PRO).
- Вебхук не разбирает типы событий: любое событие — просто триггер, после
  которого текущее состояние подписки читается из REST API RevenueCat.
  Идемпотентно и переживает события, пришедшие не по порядку.
