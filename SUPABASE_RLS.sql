-- Romanova — recommended Row Level Security for the anonymous (anon) role.
-- Spec §8: the public anon key may INSERT into `submissions` only — no SELECT/UPDATE/DELETE.
-- Run this in the Supabase SQL editor, then verify with the checks at the bottom.
--
-- NOTE: keys are NOT rotated or printed here. The anon key already lives in the client
-- (index.html) by design; RLS is what actually protects the data.

-- 1) Make sure RLS is on for the table the sell funnel writes to.
alter table public.submissions enable row level security;

-- 2) Allow anonymous INSERTs (the sell funnel). No USING clause = no read/update/delete.
drop policy if exists "anon can insert submissions" on public.submissions;
create policy "anon can insert submissions"
  on public.submissions
  for insert
  to anon
  with check (true);

-- 3) Do NOT create anon SELECT/UPDATE/DELETE policies on submissions.
--    With RLS enabled and no such policy, those operations are denied by default.
--    (submissions hold sellers' names/emails — they must not be world-readable via the anon key.)

-- 4) The shop tables are out of scope for this sell-only site. Make sure the anon role
--    cannot write them either (enable RLS, no anon write policies):
alter table public.inventory     enable row level security;
alter table public.orders        enable row level security;
alter table public.store_credit  enable row level security;
-- (Add policies only for whatever the shop genuinely needs, later.)

-- ── Verification (run with the ANON key, e.g. from the REST API or a logged-out client) ──
--   INSERT into submissions  -> should SUCCEED
--   SELECT from submissions  -> should return 0 rows / be denied
--   UPDATE/DELETE submissions -> should be denied
--
-- Quick REST probe (replace ANON_KEY; this is the public anon key, safe to use client-side):
--   curl -s -X POST 'https://ihctrnxxgvaqifvyxrmd.supabase.co/rest/v1/submissions' \
--     -H 'apikey: ANON_KEY' -H 'Authorization: Bearer ANON_KEY' \
--     -H 'Content-Type: application/json' \
--     -d '{"name":"rls test","email":"t@example.com","payout_type":"cash","estimate_low":0,"estimate_high":0,"eligible_count":0,"card_list":"{}","status":"pending"}'
--   # expect 201. Then:
--   curl -s 'https://ihctrnxxgvaqifvyxrmd.supabase.co/rest/v1/submissions?select=id&limit=1' \
--     -H 'apikey: ANON_KEY' -H 'Authorization: Bearer ANON_KEY'
--   # expect [] (RLS blocks reads). Delete the test row afterward with the service role.
