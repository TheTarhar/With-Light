# SYSTEM STRESS REPORT - 2026-04-21
**Objective:** Autonomous System Stress-Test & Product Evolution

## Scope actually executed
- Target app inspected and exercised: `with-light-app`
- Browser-driven route/keyboard/mobile checks were partially blocked by environment browser policy, so I used a mix of direct Supabase RPC/function calls, source audit, and production build verification.
- Gemini quota kill-switch was monitored. No 429 occurred during this run, and no 95% threshold event surfaced.

## Phase 1: Chaos Engineering

### 1) API Exhaustion, ABR validation RPC / Edge Function
#### What I hit
- Exercised `verify-abn` repeatedly with valid-format, invalid, and edge inputs:
  - `53004085616`
  - `51824753556`
  - `83914571673`
  - `00000000000`
  - `11111111111`
  - `12345678901`
  - formatted input `83 914 571 673`
- Ran a 20-request concurrent burst against `verify-abn`.

#### Observed behaviour
- Valid-format ABNs consistently returned:
  - `{ status: "manual_verification_required" }`
- Invalid ABNs consistently returned:
  - `{ status: "invalid", error: "Invalid ABN — could not reach the ABR." }`
- No 429s, no rate-limit response, no crash under the 20-request burst.
- Burst completed in about `1772ms` total, with individual requests mostly landing between `572ms` and `1772ms`.

#### Finding
- **ABR upstream is effectively unavailable from the edge path right now**, so the app is operating in checksum fallback mode instead of true ABR verification.
- That means the edge case you explicitly wanted, "active ABN but no GST registration", could not be conclusively validated live because the ABR dependency was unreachable.
- Current fallback behaviour is graceful, but it weakens business validation quality.

#### Extra inconsistency found
There are now **two ABN validation paths** with slightly different behaviour:
- Edge Function: `with-light-app/supabase/functions/verify-abn/index.ts`
- DB function: `public.validate_abn_via_abr(...)` in `20260420124500_final_operations_pass.sql`

This split is risky because the UI currently relies on the Edge Function, while provisioning logic in SQL relies on the DB function.

### 2) State Corruption, route auth and role checks
#### `/overseer` unauthenticated / unauthorized
From source review in `with-light-app/src/App.tsx`:
- unauthenticated users are routed away from protected areas
- `/overseer/*` renders only when `isPlatformAdmin` is true
- otherwise `/overseer/*` redirects to `/`

#### What I could verify directly
- Frontend route guard for `/overseer` is present.
- However, backend exposure is weaker than expected.

#### Critical backend finding
Calling `overseer_org_summary` with only the public anon key returned `[]` and **no authorization error**.
That means one of these is true:
- the RPC is callable by anon/authenticated users and protected only by result-shaping or empty data
- or RLS/function logic currently returns empty rather than rejecting unauthorized callers

Either way, for an admin-only control plane, that is **too soft**. It should fail closed with a permission error, not silently succeed.

#### Social Worker vs Admin org management panel
Frontend:
- admin views are wrapped in `GuardRole`
- `/admin` allows `admin` and `coordinator`
- `/worker/*` is separately role-guarded
- `/overseer/*` is platform-admin only

Backend:
- `handle_overseer_user_update(...)` explicitly checks `public.is_platform_admin()` and raises `platform_admin_required`
- so the most dangerous write path is correctly guarded server-side

#### Risk summary
- **Frontend role gating looks mostly correct**.
- **At least one overseer read RPC appears too permissive or too opaque when unauthorized**.

### 3) Concurrency, 5 simultaneous organisation creation attempts
#### What I attempted
- Simulated 5 simultaneous `provision_organisation` RPC calls.

#### What actually happened
All 5 calls failed before touching business logic with the same schema-cache error:
- `PGRST202`
- `Could not find the function public.provision_organisation(...) in the schema cache`

#### Root cause found
There is a live **signature mismatch** between code and deployed RPC shape.

Current frontend callers use the new style:
- `p_abn`

But the live schema cache hints the deployed function still expects the older shape including:
- `p_abn_verified`

This mismatch appears in source too:
- `with-light-app/src/lib/signup.ts` uses `p_abn`
- `with-light-app/src/pages/SignupWizardPage.tsx` still calls `provision_organisation` with `p_abn_verified`
- latest migration `20260420124500_final_operations_pass.sql` defines `provision_organisation(..., p_abn text, p_full_name text ...)`

#### Concurrency conclusion
- I could not meaningfully reach the insert race window because provisioning is already broken at the RPC boundary.
- That said, source review suggests a second likely race issue even after the signature is fixed:
  - duplicate protection is done with `if exists (...)` checks on `abn` and slug lookup before insert
  - without confirmed unique constraints / exception handling around the org insert itself, simultaneous requests can still race

#### Probable race risks after RPC repair
1. **ABN duplicate race** if unique constraint on `organisations.abn` is missing or not relied on.
2. **Slug collision race** if unique constraint on `organisations.slug` is missing or not relied on.
3. `user_roles` upsert uses `on conflict (user_id, role)` which may be too broad if the same user can hold the same role in different orgs.

## Phase 2: Extensive UX Exploration

### 1) The "Nour" keyboard audit
#### Limitation
A true Tab/Enter-only browser walk was blocked by browser policy in this environment.

#### Code-based UX risk review
The app uses many Radix primitives, which is generally a good sign for keyboard support.
But I still see real focus-risk zones:
- custom glassmorphism layers and heavy visual effects may hide default focus rings
- large clickable card containers in Overseer may create ambiguous tab order if non-button wrappers capture clicks
- animated route transitions may cause focus loss after navigation if focus is not restored intentionally

#### Areas to manually verify next in-browser
1. Signup wizard verify button and post-verify next step
2. Overseer expandable tenant cards
3. Dialogs and sheets in Overseer user editing and delete flows
4. Admin sidebar and nested route transitions

### 2) Deep-link testing, outdated or unauthorized sessions
#### Source findings
- `/overseer/*` is directly intercepted in `App.tsx`
- unauthenticated users get auth/public routes only
- approved-without-org users are forced into `/register`
- pending approval users are forced into `/pending-approval`
- expired trials are forced into `/trial-expired`

#### last_activity / quarantine logic findings
In `20260420124500_final_operations_pass.sql`:
- `touch_org_last_activity(p_org_id)` updates `last_activity` and clears quarantine markers
- `quarantine_inactive_organisations()` quarantines orgs after 14 days inactivity
- `purge_quarantined_organisations()` purges after 90 days

#### Gap
I found **cleanup jobs**, but not a clear frontend/session interception path that blocks a quarantined org at route-entry time.
If quarantine is meant to immediately intercept outdated or unauthorized sessions, I did not find a corresponding hard gate in `App.tsx` analogous to the trial-expiry gate.

### 3) Mobile Safari, slow network, Noura CORS fix
#### What I could verify
- `vite.config.ts` dev proxy setup looks sane for local development.
- App CSP/connect-src includes Supabase and tailnet endpoints.
- The verify-abn edge path already tolerates slow/unreachable upstream by falling back.

#### What I could not fully simulate here
- true Mobile Safari rendering/runtime quirks
- low-power CPU throttling in-browser
- >2s Deno Edge response under Safari fetch stack

#### Practical finding
Because the ABR edge path already fell back under degraded upstream conditions during this run, the app does not hard-crash on slow/unreachable upstream. That is good.
But for the specific "Noura CORS fix holds up when Deno Edge Function takes >2s" scenario, this needs one real browser-network-throttled pass once browser automation is allowed.

## Phase 3: Strategic Refinement

### 1) Two feature suggestions to automate Disability Provider onboarding
1. **ABN + NDIS prefill onboarding pack**
   - After ABN verification, auto-fetch and prefill entity name, GST status, business address, and map that into the onboarding pack.
   - Then ask only for missing provider-specific fields like NDIS registration number, service regions, support categories.
   - This cuts repetitive founder/admin typing immediately.

2. **Auto-generated compliance launch checklist from org profile**
   - Once the org is created, generate a live checklist from org type and provider status:
     - required worker documents
     - participant intake templates
     - incident and restrictive-practice registers
     - billing setup and trial expiry tasks
   - Noura should assign missing items automatically and escalate blockers before go-live.

## 2) Cleanup automation SQL audit, missing indexes
### Confirmed issue
I did **not** find supporting indexes for the new cleanup predicates on:
- `organisations.last_activity`
- `organisations.quarantined_at`
- `profiles.disabled_at`

The cleanup functions currently scan by conditions like:
- `coalesce(last_activity, created_at) < now() - interval '14 days'`
- `quarantined_at < now() - interval '90 days'`
- `disabled_at < now() - interval '30 days'`

At scale, these will degrade.

### Recommended indexes
1. On organisations quarantine sweep:
```sql
create index if not exists idx_organisations_quarantine_scan
  on public.organisations (quarantined_at)
  where terminated_at is null and purged_at is null;
```

2. On organisations activity sweep:
```sql
create index if not exists idx_organisations_last_activity
  on public.organisations (last_activity)
  where terminated_at is null and quarantined_at is null;
```

3. On disabled user cleanup:
```sql
create index if not exists idx_profiles_disabled_cleanup
  on public.profiles (disabled_at)
  where is_active = false and disabled_at is not null;
```

### Extra SQL note
Because `quarantine_inactive_organisations()` uses `coalesce(last_activity, created_at)`, a plain index on `last_activity` helps only partially. If this path becomes large, consider either:
- backfilling `last_activity` on all existing orgs and treating it as non-null operationally, or
- adding an expression index on `coalesce(last_activity, created_at)`.

## Highest-priority breakages found
1. **Provisioning RPC is broken in production/schema cache due to signature drift.**
2. **Signup code paths are internally inconsistent, one caller uses `p_abn`, another still uses `p_abn_verified`.**
3. **ABR live validation is currently degraded to fallback mode because ABR is unreachable from the edge path.**
4. **Overseer read RPC behaviour is too soft for unauthorized access, returning success with empty data instead of a hard authorization failure.**
5. **Cleanup jobs are missing indexes and will likely degrade badly at scale.**
6. **Quarantine logic exists in SQL, but I did not find an equivalent hard route/session gate for quarantined orgs in the app shell.**

## Recommended next actions, in order
1. Fix `provision_organisation` signature drift and refresh PostgREST schema cache.
2. Standardise every provisioning caller onto one RPC contract, preferably `p_abn` only.
3. Add or confirm unique constraints on `organisations.slug` and `organisations.abn`, then handle duplicate-key exceptions as the true concurrency guard.
4. Make all overseer RPCs fail closed with explicit auth errors for non-platform-admin callers.
5. Add indexes for `disabled_at`, `last_activity`, and `quarantined_at` cleanup paths.
6. Add a quarantined-org gate in app boot/routing, not just background cleanup SQL.
7. Run one final real browser pass for keyboard focus and mobile throttling once navigation policy allows it.

## Artifacts / evidence
- Source reviewed:
  - `with-light-app/src/App.tsx`
  - `with-light-app/src/pages/SignupWizardPage.tsx`
  - `with-light-app/src/lib/signup.ts`
  - `with-light-app/src/pages/OverseerDashboard.tsx`
  - `with-light-app/supabase/functions/verify-abn/index.ts`
  - `with-light-app/supabase/migrations/20260420124500_final_operations_pass.sql`
- Live checks performed against Supabase project in `.env`
- Production build completed successfully with `npm run build`

## Phase 4: Quota & Safety
- **Gemini Flash Threshold:** 95%
- **Status:** COMPLETED WITHOUT QUOTA TRIP
- **429 encountered:** No

# Deep-Dive Addendum - Hardened Schema Pass

[CRITICAL_FIXES]
- **CRITICAL: Overseer database access is still too soft at the read layer.**
  - Live anonymous calls to Overseer-scoped tables returned HTTP 200 with empty data, not a strict unauthorized failure:
    - `noura_alerts`: 200 / empty
    - `platform_audit_log`: 200 / empty
    - `organisations`: 200 / empty
  - Live anonymous call to `overseer_org_summary()` also returned `[]` with no auth error.
  - Write RPCs are better hardened: `overseer_set_tier`, `overseer_suspend_org`, and `overseer_extend_trial` now raise `platform_admin_required`.
  - Verdict: this is still a **critical security bug** under your rule, because a provider-staff or anonymous session should get a hard 401/403 style denial at the DB boundary for Overseer reads, not a silent success with zero rows.
- Root cause appears to be a dangerous mix of broad grants plus policy dependence:
  - remote schema grants `ALL` on `organisations`, `profiles`, `noura_alerts`, `platform_admins`, `platform_audit_log`, and `user_roles` to `anon` and `authenticated`
  - RLS is enabled, but the read-path semantics are fail-soft rather than explicit deny
  - `overseer_org_summary()` is `SECURITY DEFINER` and granted to `anon` and `authenticated`
- **JWT integrity for Noura chat function is good.**
  - `with-light-app/supabase/functions/chat/index.ts` is not merely checking for token presence.
  - It extracts the bearer token, calls `serviceClient.auth.getUser(jwt)`, rejects invalid/expired tokens with 401, and derives `org_id` server-side from the authenticated profile.
  - It also validates the provided anon key against `SUPABASE_ANON_KEY`.
- **State machine gap: quarantined orgs are not blocked from continuing to use authenticated AI/session flows.**
  - `chat/index.ts` only resolves `org_id` from `profiles`; it does not check `organisations.quarantined_at`, `suspended_at`, `terminated_at`, or `disabled_at` before servicing the request.
  - `touch_org_last_activity()` actively clears quarantine markers when chat succeeds.
  - That means a quarantined org can potentially self-unquarantine simply by using chat, which breaks the intended quarantine state machine.
- **Signup wizard still contains a UX/logic mismatch around slow ABN verification.**
  - `lookupAbn()` falls back gracefully, but users can sit waiting on a non-trivial network step with no skeleton or staged progress UI.
  - Any ABR response beyond a couple of seconds will feel stalled.
- **Overseer accessibility bug cluster:** many action buttons lack descriptive `aria-label`s.
  - One example is labelled (`Open upgrade drawer for ...`), but most action buttons like tier change, suspend, reactivate, pulse now, delete tenant, refresh, tab switchers, and save notes rely only on visible text/icons.
  - That is weak for screen readers in a dense admin control plane.

[PERFORMANCE_TUNING]
- The hardened indexes were applied successfully to remote:
  - `idx_organisations_quarantine_scan`
  - `idx_organisations_last_activity`
  - `idx_profiles_disabled_cleanup`
- I could verify the index definitions in applied migrations, but I did **not** run live `EXPLAIN ANALYZE` because this environment does not currently expose a direct SQL execution path for ad hoc explain plans.
- Performance concern still stands for quarantine sweep logic:
  - `quarantine_inactive_organisations()` filters on `coalesce(last_activity, created_at) < now() - interval '14 days'`
  - A plain `last_activity` index will not fully optimize that predicate if many rows still have null `last_activity`
  - Recommendation: either backfill `last_activity` for all orgs and make it operationally non-null, or add an expression index on `coalesce(last_activity, created_at)`.
- `overseer_org_summary()` may still be heavier than it looks at scale:
  - lateral owner lookup from `profiles`
  - aggregate joins on `ai_request_log` and `noura_alerts`
  - no evidence in this pass of supporting summary indexes for `ai_request_log(org_id, created_at)` or `noura_alerts(org_id, status)`
- Provisioning stress after hardening:
  - 20 concurrent anonymous attempts all failed correctly with `not_authenticated`
  - this confirms the auth boundary, but it does **not** complete the true race test for slug/ABN collisions because no authenticated synthetic test user was available in this environment
  - recommendation: next pass should run the same 20-way test under a real authenticated onboarding account to confirm unique constraints and duplicate handling under actual insert pressure
- Worker workflow code suggests likely latency hotspot in note submission UX:
  - `ShiftNoteForm` does `supabase.auth.getUser()` right before submit, then inserts the note
  - on slow mobile networks this adds unnecessary round-trip latency before the real write
  - recommendation: trust existing session state where possible, fall back to `getUser()` only on auth failure, and show a staged submitting state
- Signup onboarding likely exceeds the 5-second threshold when ABR is degraded:
  - ABN verification depends on edge function plus upstream ABR availability
  - current UI shows loading/error states but not a skeleton or optimistic staged transition
  - recommendation: add a two-step progress UI, such as `Checking ABN format` then `Confirming with ABR`, and if fallback mode is triggered, continue with an explicit background verification banner instead of holding the step hostage
- WCAG / Liquid Glass concerns:
  - many surfaces use `bg-white/[0.04]` to `bg-white/[0.06]` with `text-slate-400` or `text-slate-500`
  - on translucent glass these combinations are very likely to miss WCAG 2.2 contrast minima, especially for 10px to 11px utility text in Overseer cards and labels
  - focus visibility is also at risk where buttons and inputs use `outline-none` without an obvious compensating strong focus ring in local classes

[PRODUCT_EVOLUTION]
- Three high-value Noura automations for NDIS compliance reporting:
  1. Auto-generate participant progress summaries from shift notes across a date range, grouped by goal and support domain.
  2. Detect missing mandatory documentation patterns, for example repeated support delivery with no matching clinical note, incident follow-up, or expiring compliance docs, then create compliance tasks automatically.
  3. Draft audit-ready monthly provider reports that combine participant outcomes, incident trends, staff compliance gaps, and service-delivery exceptions into one export for management review.
- Social Worker daily workflow, code-based assessment:
  - log in and sign-out paths exist
  - participant selection and shift-note submission flow exists in `ShiftNoteForm`
  - session-expiry handling is present and reasonably clear
  - but I could not execute a full browser-driven workflow here because browser navigation remains policy-blocked in this environment
- Best next UX lift for social workers:
  - prefetch assigned participants and cache locally before entering the note form
  - reduce submit-time auth checks
  - add clearer success states for clock in/out and note save when network is weak
- Onboarding friction improvements:
  1. Add skeleton/progress states around ABN verification.
  2. Autofill organisation name immediately from ABR/manual-verification result when available, but visually confirm the autofill so it doesn’t feel like a sudden form mutation.
  3. Remove the post-provision redundant `organisations.update({ abn: cleanAbn })` write when the RPC already persists ABN, because that is an extra network hop and another failure point.
