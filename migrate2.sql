-- ============================================================
--  Profiles: pictures. Paste into Supabase -> SQL Editor -> Run.
--  Safe to run more than once.
-- ============================================================

-- A small square image, stored inline as a data URL. The app shrinks
-- whatever you pick to 160px before it ever gets here, so a row stays
-- a few kilobytes rather than the several megabytes a phone photo is.
alter table public.profiles
  add column if not exists avatar text not null default '';

-- Presence ("who's online") rides on Realtime and needs no tables, but
-- the profiles table must be in the publication so a changed name or
-- picture reaches everyone without a refresh. Harmless if already there.
do $$
begin
  begin
    alter publication supabase_realtime add table public.profiles;
  exception when duplicate_object then null;
  end;
end $$;

select 'ready' as status,
       (select count(*) from public.profiles)       as accounts,
       (select count(*) from public.allowed_emails) as approved;
