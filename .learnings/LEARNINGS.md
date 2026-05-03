## [LRN-20260405-001] correction

**Logged**: 2026-04-04T23:04:00+10:00
**Priority**: medium
**Status**: pending
**Area**: config

### Summary
When the user says “not that” after a monitor/system message, confirm the target task before answering and avoid mixing unrelated monitor results into active Xero/bookkeeping work.

### Details
I answered a question about a NOD monitor failure when the user was asking about Xero progress. The user explicitly corrected this and asked to remove NOD access attempts.

### Suggested Action
Keep heartbeat/monitor files truly empty when no periodic checks are desired, and separate monitor updates from active task threads.

### Metadata
- Source: user_feedback
- Related Files: /home/taha/.openclaw/workspace/HEARTBEAT.md
- Tags: correction, heartbeat, monitor, xero

---

## [LRN-20260418-001] correction

**Logged**: 2026-04-18T21:13:00+10:00
**Priority**: high
**Status**: pending
**Area**: docs

### Summary
Do not anchor tender quotations to top-level project budget percentages without validating trade scope from actual drawings, schedules, and package boundaries.

### Details
While pricing the TAFE Campbelltown tender, I incorrectly treated the builder's total project budget as a direct basis for Neura's subcontract quote and then applied a broad percentage shortcut. The user corrected that the builder's scope value was the overall project value and the electrical/data/AV/security package would be only a fraction of that. For tender pricing, especially refurbishment jobs, percentage heuristics can be a quick sense-check only after reading the actual trade drawings/specs and identifying scope intensity, room counts, AV/security inclusions, demolition extent, and preliminaries.

### Suggested Action
For future subcontract quotes, first extract scope intensity from tender documents and build an allowance-based breakdown before using percentage-of-build cost only as a secondary validation check.

### Metadata
- Source: user_feedback
- Related Files: /home/taha/.openclaw/workspace/TAFE_Campbelltown_Xero_Quote_Draft.md
- Tags: tender, estimation, pricing, correction

---
## [LRN-20260430-001] correction

**Logged**: 2026-04-30T11:00:00Z
**Priority**: high
**Status**: pending
**Area**: backend

### Summary
Do not derive worker org context for shift notes from `public.workers`; `shift_notes.worker_id` points to `auth.users`, and org context lives on `profiles` / `user_roles`.

### Details
A null `shift_notes.org_id` backfill migration incorrectly joined `shift_notes.worker_id` to `public.workers.id` and assumed `workers.org_id` existed. In this schema, `public.workers` is a legacy table without `org_id`, while authenticated worker tenancy is resolved via `profiles.user_id -> profiles.org_id` with fallback to `user_roles.user_id -> user_roles.org_id`.

### Suggested Action
Fix the backfill migration to join through `profiles` first and `user_roles` second, matching `current_user_org_id()` and other org-resolution code paths.

### Metadata
- Source: user_feedback
- Related Files: /home/taha/.openclaw/workspace/with-light-app/supabase/migrations/20260430193000_fix_null_org_id.sql
- Tags: supabase, org_id, shift_notes, profiles, user_roles

---
