-- ============================================================
--  Local Pages — profiles, pictures and "who's here"
--  Paste the whole file into Supabase → SQL Editor → Run.
--  Safe to run more than once.
-- ============================================================

-- ---------- 1. profile pictures ----------
-- A small square image kept inline as a data URL. The app centre-crops
-- and shrinks whatever you pick to 160px before it ever gets here, so a
-- row stays a few kilobytes rather than the megabytes a phone photo is.
alter table public.profiles
  add column if not exists avatar text not null default '';

-- ---------- 2. who's here ----------
-- Realtime's built-in presence is not enabled on this project (a channel
-- subscribes and track() reports success, but the roster never comes
-- back), so the app keeps its own: every open browser stamps its row
-- about every 20 seconds, and anyone stamped in the last minute counts
-- as online.
create table if not exists public.presence (
  user_id uuid primary key references auth.users on delete cascade,
  name    text not null default '',
  seen_at timestamptz not null default now()
);

alter table public.presence enable row level security;

-- Everyone signed in sees who else is about; you may only stamp yourself.
drop policy if exists presence_read on public.presence;
drop policy if exists presence_self on public.presence;
create policy presence_read on public.presence
  for select to authenticated using (true);
create policy presence_self on public.presence
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- 3. live updates ----------
do $$
declare t text;
begin
  foreach t in array array['profiles','presence']
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ---------- 4. check ----------
select 'ready'                                          as status,
       (select count(*) from public.profiles)           as accounts,
       (select count(*) from public.allowed_emails)     as approved,
       (select count(*) from public.presence)           as here_now;
