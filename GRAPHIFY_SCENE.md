# GRAPHIFY_SCENE

## Purpose
This file is a fast-start scene setter for Claude Code before the overnight With Light run. It maps the current product shape, the routes that matter commercially, and the brand voice that should anchor the coming SEO audit and content decisions.

## Product Snapshot
**With Light App** is a multi-tenant NDIS operations platform.

Core promise: an NDIS provider's team delivers care, while **With Light** and its AI operations manager **Noura** handle compliance visibility, admin reduction, onboarding, rostering awareness, and operational follow-through.

## Core Architecture

### 1. Frontend
- **Framework:** React 18 + TypeScript
- **Build tool:** Vite
- **Routing:** `react-router-dom`
- **Data/state:** React Query for async data, React context for auth/language/theme
- **UI style:** dark-first, premium glassmorphism, Apple-inspired polish, conversion-led marketing on public pages
- **Mobile wrapper capability:** Capacitor dependencies are present for Android/iOS

### 2. Auth + Session Layer
- Supabase Auth drives sign-up, sign-in, session bootstrap, email verification, and sign-out.
- `AuthContext` resolves:
  - current session/user
  - role(s): `admin`, `coordinator`, `support_worker`, `family`
  - approval state
  - organisation membership
  - subscription/trial state
  - platform admin / Overseer access
- The app routes users based on auth state, org provisioning state, approval state, role, and trial status.

### 3. Backend
- **Backend platform:** Supabase
- **Key backend layers:**
  - Postgres database
  - RPC functions, especially organisation provisioning
  - Row-level security and role-aware access patterns
  - Edge Functions for tasks like ABN verification
  - Storage bucket usage for uploaded documents
  - Auth and session handling

### 4. Multi-tenant Data Model
The app is organisation-centric.

Important entities and patterns visible from current code and migrations:
- `organisations`
- `profiles`
- `user_roles`
- `platform_admins`
- `shift_notes`
- `participant_checkins`
- `ai_om_triage`
- compliance-related tables, incidents, registers, billing/invoicing-related structures

Business logic assumes each user belongs to an organisation context, with role-based access layered on top.

### 5. AI / Automation Layer
**Noura** is not a side feature. It is the product identity anchor.

Current platform direction shows Noura acting as an **AI Operations Manager** that:
- monitors compliance posture
- flags risks from operational data
- triages incidents and evidence gaps
- surfaces admin actions instead of making users dig for them
- supports onboarding and product differentiation on the landing experience

There is already AI OM infrastructure in Supabase migrations, including:
- triage tables
- webhook dispatching
- autonomous audit logic for shift notes

## Route Map: High-Priority Business Surfaces

### A. Landing / Acquisition
**Primary public routes:**
- `/` → `PublicLanding`
- `/pricing` → `PricingPage`
- `/auth` → `AuthPage`
- `/register` → `RegisterPage`
- `/onboarding-brand` → `OnboardingBrandChat`

#### Why this matters
This is the growth engine.

The landing stack is built to sell the transformation, not just list features. It positions With Light as the premium AI-backed operating system for NDIS providers, with Noura as the differentiator.

#### Messaging priorities
- reduce admin burden
- improve compliance confidence
- prevent revenue leakage from missed notes/claims/tasks
- create calm operational control
- frame Noura as always-on operational intelligence

### B. Onboarding / Activation
**Primary onboarding routes:**
- `/register`
- `/onboarding-brand`
- authenticated no-org flow → `SignupWizardPage`
- `/checkout` currently redirects into register/onboarding flow

#### Onboarding structure
The onboarding journey is high-value because it directly converts interest into an activated workspace.

Key stages present in the codebase:
1. account creation
2. organisation details
3. ABN verification / organisation provisioning
4. provider type selection
5. Noura introduction and optional initial document upload
6. handoff into `/admin`

#### Why this matters
This route family is where the business proves:
- trust
- legitimacy
- ease of setup
- speed to first value

Anything SEO-driven that lands a prospect here should preserve momentum and reduce friction.

### C. Admin / Core Retention Surface
**Primary admin route:**
- `/admin`

**Important admin sub-routes:**
- `/admin/shifts`
- `/admin/calendar`
- `/admin/participants`
- `/admin/tasks`
- `/admin/sil-roster`
- `/admin/compliance`
- `/admin/registers`
- `/admin/incidents`
- `/admin/templates`
- `/admin/referrals`
- `/admin/team`
- `/admin/directory`
- `/admin/timesheets`
- `/admin/invoices`
- `/admin/billing`
- `/admin/ram`
- `/admin/noura`
- `/admin/settings`

#### Why this matters
This is the product's economic core. If landing converts demand, admin retains it.

The admin experience is where With Light becomes the daily operating system for a provider. It is the strongest proof of product value because it connects compliance, workforce operations, participant oversight, billing, and AI-led triage in one place.

## Business Route Priority Order
If Claude Code or any overnight audit has to weight pages by business importance, use this order:

1. **Landing (`/`)**
   - acquisition, SEO, first impression, market positioning
2. **Register + onboarding flow (`/register`, `/onboarding-brand`, onboarding wizard)**
   - activation, conversion, trust, lead-to-workspace creation
3. **Admin dashboard (`/admin` and key sub-pages)**
   - retention, daily value, product stickiness, expansion

Short version:
- **Landing sells the dream**
- **Onboarding closes the gap between interest and setup**
- **Admin delivers the promise**

## Brand Voice for SEO Audit

### Core voice
**Premium, calm, operationally sharp, quietly powerful.**

With Light should sound like:
- a high-trust operator
- deeply familiar with NDIS realities
- anti-chaos, anti-admin-sprawl
- technologically advanced without sounding gimmicky
- confident enough to be simple

### Tone traits
- **Clear, not fluffy**
- **Authoritative, not corporate-stiff**
- **Empathetic to provider stress, not sentimental**
- **Commercially intelligent, not generic SaaS-speak**
- **Modern and premium, not bureaucratic**
- **Australian and grounded, not Silicon Valley cliché**

### What the voice should emphasise
- operational relief
- compliance confidence
- proactive oversight
- time saved
- fewer missed tasks, expiring documents, or delayed claims
- care teams staying focused on participants, not admin burden
- Noura as an always-on operations manager, not a chatbot toy

### What to avoid
- generic "AI revolution" hype
- vague productivity claims with no operational context
- sounding like a government form
- sounding cheap, loud, or salesy
- overusing compliance jargon without a practical user outcome

### Positioning line to preserve
A strong distilled framing from the live marketing direction is:
- **Your team delivers care. Noura handles the rest.**

That framing should influence SEO page messaging, headings, and supporting copy.

## SEO Framing Notes
For the upcoming SEO audit, Claude Code should treat the site as a business-critical conversion surface aimed at:
- NDIS providers
- support coordination and related provider operations teams
- organisations overwhelmed by compliance/admin/rostering complexity

The copy should likely optimise around themes such as:
- NDIS software
- NDIS compliance software
- NDIS provider operations platform
- AI for NDIS providers
- shift notes, compliance, rostering, incident visibility, participant management

But the brand should still read as premium and outcome-driven, not keyword-stuffed.

## Working Assumptions for Overnight Run
- Frontend is React/Vite and route-driven.
- Backend is Supabase with strong multi-tenant business logic.
- Noura is central to product differentiation.
- The highest-leverage surfaces are Landing, Onboarding, and Admin.
- SEO recommendations should strengthen conversion quality, not just traffic volume.
- Any content strategy should preserve the current premium, operational, NDIS-specific brand posture.

## Useful Source Anchors
- `with-light-app/src/App.tsx`
- `with-light-app/src/contexts/AuthContext.tsx`
- `with-light-app/src/pages/PublicLanding.tsx`
- `with-light-app/src/pages/RegisterPage.tsx`
- `with-light-app/src/pages/SignupWizardPage.tsx`
- `with-light-app/src/pages/AdminDashboard.tsx`
- `with-light-app/supabase/migrations/20260419180000_ai_om_infrastructure.sql`
- `with-light-app/supabase/migrations/20260420112500_overseer_user_rpc_and_abn_enforcement.sql`

## Final Brief for Claude Code
Read this file as the business and product context layer before doing the overnight run.

When making SEO, IA, UX copy, or route-priority decisions:
- optimise for **trust + activation + retention**
- preserve the **Noura-led premium operations** narrative
- treat **Landing, Onboarding, and Admin** as the three strategic pillars
- keep the brand voice **calm, sharp, modern, and operationally credible**
