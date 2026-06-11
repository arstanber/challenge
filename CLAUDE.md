# The Challenge — Project Guide

## What This Is

**The Challenge** is a Russian-language iOS habit-tracking app with AI photo verification. Users create goals, submit photo proof of completion, and Claude checks the photo against the task description. No cheating.

Two products live in this repo:

| Product | Path | Stack |
|---|---|---|
| iOS app | `Challenge/` | Swift 6, SwiftUI, @Observable, Supabase |
| Landing site | `website/` | Pure HTML/CSS/JS, self-hosted fonts, GitHub Pages |

---

## iOS App

### Tech Stack
- **Language:** Swift 6, strict concurrency
- **UI:** SwiftUI, @Observable (no ObservableObject/Combine)
- **Backend:** Supabase (Postgres + Auth + Storage + Edge Functions)
- **AI verification:** Claude via Supabase Edge Function `verify-report`
- **Auth:** Apple Sign In + Google Sign In
- **Payments:** StoreKit 2 (`StoreService`)
- **Analytics:** Aptabase (`AnalyticsService`)
- **Notifications:** APNs + Telegram bot (`@thechallengeapp_bot`)
- **Font:** Manrope (local, `Utils/Font+Manrope.swift`)

### Architecture

```
ChallengeApp.swift          ← @main, injects AuthService into environment
ContentView / RootView      ← Auth gate: OnboardingView | MainTabView
Models/                     ← Pure data structs (Activity, Workspace, Family, User…)
ViewModels/                 ← @Observable, own their state + async logic
Services/                   ← Singletons (AuthService, SupabaseService, AIVerificationService…)
Views/
  Main/                     ← Full screens (HomeView, ActivitiesView, SettingsView…)
  Activity/                 ← Task creation, camera, AI result
  Components/               ← Reusable pieces (ActivityRowView, StreakBadgeView…)
  Onboarding/               ← Onboarding flow
  Profile/                  ← Family, profile, Telegram link
Analytics/                  ← WeeklyReport, YearInReview, StreakRisk
Gamification/               ← GamificationEngine, QuestEngine
```

### Key Services

| Service | Responsibility |
|---|---|
| `AuthService` | Apple/Google sign-in, session management, `currentUser` |
| `SupabaseService` | Shared `supabase` client (singleton) |
| `AIVerificationService` | Calls edge function `verify-report`, returns `approved/excused/explanation` |
| `StoreService` | StoreKit 2 — `monthly` / `family` subscriptions |
| `NotificationService` | APNs token save, local scheduling |
| `AnalyticsService` | Aptabase wrapper (key: `A-EU-7608056201`) |
| `GamificationEngine` | Streaks, milestones, quests |
| `ConnectorService` | HealthKit + OAuth data connectors |

### Constants (`Utils/Constants.swift`)
- Supabase URL: `https://tvuvfuguxjvzyzsjnepr.supabase.co`
- Free tier: 3 activities max, 10 AI verifications/month
- Streak milestones: 7, 14, 30, 100 days
- Streak day rule: >= 75% of the recurring tasks scheduled that day (min 1) -- `streakDailyCompletionRatio` / `dailyStreakGoal(scheduledToday:)` MUST match the server engine (`compute_user_streak`, migration `20260612_streak_75_percent.sql`); change them together. The `p_min` parameter is legacy and ignored.
- IAP product IDs: `com.challenge.premium.monthly`, `com.challenge.premium.family`

### Task core (single source of truth)
- "Done today" = report row in `reports` (`ai_result` approved/not_applicable/pending counts; rejected never counts; excused holds the streak without counting). `Services/TaskEngine.swift` owns this state in the app; UserDefaults is only an optimistic offline overlay.
- Streaks are computed ONLY by the server engine (`compute_activity_streak` / `compute_user_streak`); a trigger on `reports` keeps `activities.streak_current/streak_best` fresh; the app reads via the `refresh_my_streaks` RPC. Do not add new client-side streak algorithms.
- `activities.schedule_days` smallint[] = ISO weekdays (1=Mon..7=Sun), NULL/empty = every day. Swift `Calendar.weekday` is Sun=1 -- convert via `Activity.isoWeekday(of:)`.
- Server-side day bucketing uses `users.timezone` (synced from the device on login).

### Supabase Edge Functions (`supabase/functions/`)
- `verify-report` — main AI verification, calls Claude, writes result back to DB
- Other functions in `supabase/functions/`

### Database Migrations (`supabase/migrations/`)
Migrations are date-prefixed SQL files. Always create a new migration file — never edit existing ones.

### Swift Conventions
- Use `@Observable` + `@State`/`@Bindable`, never `@ObservedObject`/`@StateObject`
- `async/await` throughout, no Combine
- Actors for services with shared mutable state
- No force-unwraps except where truly impossible to be nil (explain in comment)
- No `print()` — use `os.Logger`: `import os.log`, then `private let logger = Logger(subsystem: "com.challenge", category: "<ClassName>")`. Use `logger.error(...)` for errors, `logger.debug(...)` for debug info. File-level `private let` for enums/static types, stored property for classes/structs.
- Em-dashes banned in UI strings — use two hyphens (`--`) or rewrite

### Build
Open `Challenge.xcodeproj` in Xcode. Requires iOS 17+. Run on simulator or device.

---

## Landing Website

### Stack
- **Host:** GitHub Pages → `arstanber/the-challenge-site` → `thechallenges.app`
- **No build tools** — plain HTML/CSS/JS, edit and push
- **Fonts:** Self-hosted in `assets/fonts/` (no Google Fonts CDN)
  - `Stack Sans Headline` → all `h1–h4`, display numbers, section titles
  - `Google Sans Flex` (variable) → body, UI, buttons, nav
- **Icons:** Tabler Icons CDN (`ti` webfont classes)
- **Accent color:** `#7c4df0` (violet)
- **Language:** Russian throughout

### File Map

```
website/
  index.html          ← Main landing page (10 sections)
  features.html       ← Feature deep-dive
  support.html        ← Support / FAQ
  privacy.html        ← Privacy policy
  terms.html          ← Terms of use
  styles.css          ← Single stylesheet — design tokens at top
  script.js           ← Scroll reveal, nav, hamburger
  assets/
    icon.png          ← App icon
    fonts/            ← Self-hosted TTF files
    screens/          ← App screenshots (today.png, ai_planner.png, list_detail.png)
```

### Landing Page Sections (index.html)
1. Header/Nav — floating pill, blur backdrop
2. Hero — dark gradient, device mockup, floating badges
3. Double-row ticker — forward + reverse marquee
4. Features intro — large headline section break
5. AI Spotlight — split layout, 3-step verification flow
6. Features bento — 6 cells grid
7. Stats band — dark card: 94% accuracy / 47-day streak / 12K+ tasks
8. How it works — 3 steps
9. Testimonials — 3 cards
10. FAQ home — sticky sidebar + `<details>` accordions
11. Download — QR card + CTA

### CSS Conventions
- Design tokens in `:root` at top of `styles.css`
- `--sp: 120px` — standard section padding
- `--radius`, `--radius-sm`, `--radius-lg` — consistent border-radius
- `.reveal` / `.reveal-r` — scroll-in classes, toggled by IntersectionObserver in `script.js`
- `--delay` CSS var on elements for staggered animations
- No em-dashes (`—` or `–`) anywhere in HTML

### Deploy
```bash
cd website
git add -A
git commit -m "message"
git push origin main
# → auto-deploys to thechallenges.app via GitHub Pages
```

---

## Repo Layout

```
Challenge/              ← iOS app source
  Models/
  Services/
  ViewModels/
  Views/
  Analytics/
  Gamification/
  Utils/
Challenge.xcodeproj/
supabase/
  functions/            ← Edge functions (Deno/TypeScript)
  migrations/           ← SQL migration files
website/                ← Static landing site
  assets/
  *.html
  styles.css
  script.js
.claude/
  commands/             ← Slash commands
  skills/               ← Project skills
```

---

## Contact / Accounts
- **Developer:** arstanber
- **Support email:** berdongar@gmail.com
- **Supabase project:** tvuvfuguxjvzyzsjnepr
- **GitHub repo (app):** https://github.com/arstanber/challenge
- **GitHub repo (site):** https://github.com/arstanber/the-challenge-site
- **Telegram bot:** @thechallengeapp_bot

---

## Workflow
- After EVERY completed subtask: `git add . && git commit -m "..." && git push`
- Commit format: `feat:`, `fix:`, `refactor:`, `chore:`
- Never leave uncommitted changes
