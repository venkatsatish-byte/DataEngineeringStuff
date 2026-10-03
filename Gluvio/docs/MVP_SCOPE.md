# MVP scope and roadmap

The MVP is the smallest version that is safe, useful every day, and teaches
something a glucose meter's own app doesn't: **how meals and walks affect *my*
glucose.** Everything else waits until real users have tried it.

## MVP: TestFlight with about 20 people (≈ 8–10 weeks for one engineer)

### iPhone

| Area | In the MVP |
|---|---|
| Onboarding | Welcome, disclaimer acceptance, units, target range (default 70–180 mg/dL), "Do you use a CGM?", Health and notification permission primers |
| Glucose | Import from Apple Health (CGM and meters); manual entry with time and context (fasting / before meal / after meal / bedtime); edit and delete own entries; mg/dL ↔ mmol/L |
| Today screen | Latest reading with age and trend arrow (CGM); today's average, time in range (CGM) or % of readings in range (fingersticks), lows and highs count; today's chart with the target band shaded |
| Trends | 7- and 30-day charts (daily average with low–high spread), time-in-range bar, estimated A1C/GMI with its label and data requirements |
| Meals | Log a meal with type, carbs (typed in) and optional photo; per-meal glucose response; "check 2 h after this meal" reminder for fingerstick users |
| Activity | Today's steps and active minutes against goals; workouts on the glucose chart; post-meal walk prompt |
| Guide | Plate-method visual and a short list of low-GI swaps, as static content reviewed by a clinician |
| Safety | Urgent low/high screen, stale-data labels, disclaimer in Settings |
| Reminders | Glucose checks and post-meal walks (local notifications) |

### Apple Watch

| Area | In the MVP |
|---|---|
| Main screen | Latest reading with age, trend arrow and band color; today's time in range |
| Quick log | Glucose (Digital Crown picker) and water |
| Complications | Latest reading (circular, inline, corner) and time in range (rectangular), each showing the reading's time |

### Not in the MVP, on purpose

- **PDF report:** valuable, but it needs the trends to be trusted first.
- **Haptic out-of-range alerts:** see "Open question 2"; they can't be made reliable
  enough to promise.
- **Food database and carb lookup:** licensing and accuracy work.
- **Sleep and heart-rate correlations:** need weeks of data before they mean anything.
- **iPhone Home Screen widgets:** cheap once the Watch complications exist; first in v1.

## v1: App Store launch

- PDF report for the doctor: 14- or 30-day summary, time-in-range bar, daily
  overlay (AGP-style), meal-response highlights and logbook, with the disclaimer
  on every page
- iPhone widgets (small: latest reading; medium: today's chart) and Lock Screen
  widgets
- Food search with carb values (USDA FoodData Central, which is public domain)
  and saved favorite meals
- A low-GI swaps library and exercise ideas (walks after meals, beginner
  strength routines, chair exercises)
- Insights:
  - "Meals followed by a walk rose X mg/dL less on average"
  - Glucose on days with more vs fewer steps
  - Glucose after nights with more vs less sleep
- Watch: meal quick log, hydration and post-meal walk reminders, informational
  out-of-range haptic (if approved)
- Medication reminders, with a free-text label only and no doses
- Accessibility pass (VoiceOver labels on charts, Dynamic Type), Spanish
  localization

## v2: deeper personalization

- Pattern detection, e.g. "your fasting readings are often higher on Mondays"
- Photo-based carb estimation on the device, shown as a suggestion the user confirms
- Siri and Shortcuts (App Intents): "Log my blood sugar"
- A Live Activity after meals, counting down to the 2-hour check
- A standalone Watch app (works without the iPhone nearby)
- Direct CGM partner integrations for fresher data, only with regulatory sign-off
- Clinician share links, only if a privacy-preserving design is found (this breaks
  the "no network" rule, so it needs its own decision)

## Screen map

```
iPhone tabs:   Today │ Trends │ ＋Log │ Guide │ Settings
                 │       │       │       │        └ Targets, units, reminders, Health access,
                 │       │       │       │          disclaimer, privacy, (v1) export report
                 │       │       │       └ Plate method, low-GI swaps, exercise ideas
                 │       │       └ Sheet: Glucose │ Meal │ Water
                 │       └ 1 / 7 / 30 days, time in range, estimated A1C, meal responses
                 └ Latest reading, today's stats and chart, activity rings, next reminder

Watch:         Latest reading ─(swipe)─▶ Today's time in range ─(button)─▶ Quick log
Urgent screen: shown over everything when a new reading is urgent
```

## App Store review: what to prepare

Kept short here; this becomes a full checklist before submission.

- **1.4.1 (medical apps):** medical apps get extra scrutiny. Disclose how the
  estimates are calculated (GMI and ADAG formulas cited in the app), remind users
  to consult their doctor, and make no diagnostic or treatment claims.
- **5.1.3 (health data):**
  - No health data in the app's own iCloud storage.
  - No health data used for advertising or data mining.
  - Never write inaccurate data into Apple Health.
  - A privacy policy is required.
- **2.5.1:** HealthKit use must be clearly visible in the app and in the
  description.
- **Permission text:** clear HealthKit purpose strings, and requests made at the
  moment of need.
- **Reviewer notes:** a demo mode with sample data, so the reviewer can see the
  charts without a CGM.
- **Regulation:** FDA (US) and EU MDR. The app is designed to stay a general
  wellness and self-management tool. Real-time CGM display with alerts, or any
  dosing logic, would change that, so get advice from a regulatory consultant
  before v1.

## Open questions

These change what gets built, so they come before code.

1. **Where should the code live?**
   It currently sits in `Gluvio/` inside DataEngineeringStuff. A
   dedicated repository would be cleaner for an app; create an empty one and it
   can be moved there.
2. **What should out-of-range alerts promise?**
   CGM data can reach Apple Health hours late, and background refresh is rationed.
   Is "informational only; your CGM app remains your alarm" acceptable, or are
   real-time alerts essential? Real-time would mean CGM partner APIs and likely FDA
   clearance.
3. **Is it acceptable to drop iCloud sync?**
   The app would sync through Apple Health instead, which is what Guideline 5.1.3
   points to.
4. **Who will review the clinical content?**
   A certified diabetes educator or physician needs to sign off on the urgent
   low/high wording (including whether to show the 15-15 rule), the default
   urgent thresholds, and the diet and exercise content.
5. **Which countries are you launching in?**
   This sets the default units (mg/dL in the US, mmol/L in the UK, Canada and
   Australia), the regulators, and food database licensing.
6. **Which CGMs do you expect users to have?**
   Dexcom, Libre, or mostly fingersticks? This decides whether the MVP leads with
   CGM charts or with fingerstick logging and reminders.
7. **Do you have a Mac with Xcode and an Apple Developer account?**
   iOS and watchOS apps can only be built and run there; the HealthKit entitlement
   needs a paid account.
8. **What's the name?**
   Decided: **Gluvio**.
