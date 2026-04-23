# DB_SCHEMA_CURRENT

Source of truth pulled from current Supabase migrations.

CREATE TABLE IF NOT EXISTS "public"."participants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "full_name" "text" NOT NULL,
    "date_of_birth" "date",
    "ndis_number" "text",
    "ndis_plan_start" "date",
    "ndis_plan_end" "date",
    "goals" "text"[],
    "notes" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "address" "text",
    "address_lat" numeric,
    "address_lng" numeric,
    "participant_status" "public"."participant_status" DEFAULT 'active'::"public"."participant_status" NOT NULL,
    "referred_by" "uuid",
    "referred_at" timestamp with time zone,
    "referral_notes" "text",
    "enable_birthday_reminder" boolean DEFAULT true NOT NULL,
    "ndis_funded_amount" numeric(10,2),
    "ndis_plan_managed_by" "text" DEFAULT 'agency'::"text",
    "support_category" "text",
    "plan_review_date" "date",
    "general_notes" "jsonb" DEFAULT '[]'::"jsonb",
    "allied_health_contacts" "jsonb" DEFAULT '[]'::"jsonb",
    "org_id" "uuid" DEFAULT "public"."get_my_org_id"(),
    "phone" "text",
    "email" "text",
    CONSTRAINT "participants_ndis_plan_managed_by_check" CHECK (("ndis_plan_managed_by" = ANY (ARRAY['agency'::"text", 'plan_managed'::"text", 'self_managed'::"text"])))
);


CREATE TABLE IF NOT EXISTS "public"."shift_notes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "worker_id" "uuid",
    "participant_id" "uuid",
    "shift_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "scheduled_start_time" timestamp with time zone,
    "clock_out_time" timestamp with time zone,
    "clock_in_lat" numeric(10,8),
    "clock_in_lng" numeric(11,8),
    "clock_out_lat" numeric(10,8),
    "clock_out_lng" numeric(11,8),
    "data_section" "text",
    "assessment_section" "text",
    "plan_section" "text",
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "gps_lat" numeric,
    "gps_lng" numeric,
    "hourly_rate" numeric DEFAULT 35.00,
    "high_risk_flag" boolean DEFAULT false,
    "high_risk_keywords" "text"[] DEFAULT '{}'::"text"[],
    "clock_in_time" timestamp without time zone,
    "polished_content" "text",
    "raw_content" "text",
    "original_note" "text",
    "polished_note" "text",
    "org_id" "uuid",
    "created_by" "uuid",
    "authored_by_role" "text",
    "voice_note_url" "text",
    "ai_assessment_severity" "text",
    "ai_assessment_summary" "text",
    "ai_assessment_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "ai_assessed_at" timestamp with time zone,
    "ai_compliance_status" "text" DEFAULT 'pending'::"text",
    "ai_compliance_score" integer,
    "ai_compliance_flags" "jsonb",
    "ai_analyzed_at" timestamp with time zone,
    CONSTRAINT "shift_notes_ai_assessment_severity_check" CHECK (("ai_assessment_severity" = ANY (ARRAY['low'::"text", 'medium'::"text", 'high'::"text"]))),
    CONSTRAINT "shift_notes_ai_assessment_status_check" CHECK (("ai_assessment_status" = ANY (ARRAY['pending'::"text", 'processing'::"text", 'completed'::"text", 'failed'::"text", 'skipped'::"text"]))),
    CONSTRAINT "shift_notes_authored_by_role_check" CHECK (("authored_by_role" = ANY (ARRAY['worker'::"text", 'admin'::"text", 'coordinator'::"text"]))),
    CONSTRAINT "shift_notes_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'clocked_in'::"text", 'clocked_out'::"text", 'submitted'::"text"])))
);


CREATE TABLE IF NOT EXISTS "public"."timesheets" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "worker_id" "uuid" NOT NULL,
    "period_start" "date" NOT NULL,
    "period_end" "date" NOT NULL,
    "total_hours" numeric(8,2) DEFAULT 0 NOT NULL,
    "travel_hours" numeric(8,2) DEFAULT 0 NOT NULL,
    "travel_kms" numeric(8,2) DEFAULT 0 NOT NULL,
    "status" "public"."timesheet_status" DEFAULT 'draft'::"public"."timesheet_status" NOT NULL,
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "org_id" "uuid"
);


CREATE TABLE IF NOT EXISTS "public"."billing_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "org_id" "uuid" NOT NULL,
    "event_type" "text" NOT NULL,
    "stripe_event_id" "text",
    "gc_event_id" "text",
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


CREATE TABLE IF NOT EXISTS "public"."invoices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "shift_id" "uuid",
    "invoice_number" "text",
    "invoice_date" "date",
    "due_date" "date",
    "total_amount" numeric(10,2),
    "status" "text" DEFAULT 'draft'::"text",
    "xero_invoice_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "org_id" "uuid"
);


create table if not exists public.service_bookings (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  participant_id uuid references public.participants(id) on delete set null,
  source_text text not null,
  allocated_budget numeric(12,2),
  start_date date,
  end_date date,
  parser_status text not null default 'parsed_pending_review',
  parser_model text,
  parser_confidence numeric(5,4),
  parser_payload jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_bookings_allocated_budget_nonnegative check (allocated_budget is null or allocated_budget >= 0),
  constraint service_bookings_date_order check (start_date is null or end_date is null or start_date <= end_date)
);
