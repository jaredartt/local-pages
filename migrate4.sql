-- ============================================================
--  Local Pages — step icons and task assignments
--  Paste the whole file into Supabase → SQL Editor → Run.
--  Safe to run more than once.
-- ============================================================

-- ---------- 1. step icons ----------
-- A Material Symbols icon name (e.g. "edit", "photo_camera"), or ''
-- for the default placeholder. Picked from the app's icon search.
alter table public.steps
  add column if not exists icon text not null default '';

-- ---------- 2. assignments ----------
-- Who is on the hook for a given step, for a given month x edition.
-- One row per cell, same shape as `entries`. completed_at is a separate,
-- editable record of when THIS assignment was wrapped up -- it does not
-- drive the step's own done/not-done state, which stays whatever
-- `entries` says (so anyone finishing the step finishes it for everyone,
-- exactly as before). Deleting the row means "nobody assigned".
create table if not exists public.assignments (
  month_id     text not null references public.months(id)   on delete cascade,
  edition_id   text not null references public.editions(id) on delete cascade,
  step_id      text not null references public.steps(id)    on delete cascade,
  user_id      uuid references auth.users on delete set null,
  completed_at date,
  updated_at   timestamptz not null default now(),
  updated_by   uuid references auth.users,
  primary key (month_id, edition_id, step_id)
);
create index if not exists assignments_user on public.assignments (user_id);

alter table public.assignments enable row level security;

-- Same rule as everything else in this app: signed in -> read everything,
-- full access (is_admin) -> change anything. Any full-access teammate can
-- reassign or re-date anyone else's task, which is the point of "Team".
drop policy if exists read_all     on public.assignments;
drop policy if exists write_admin  on public.assignments;
create policy read_all    on public.assignments for select to authenticated using (true);
create policy write_admin on public.assignments for all    to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------- 3. live updates ----------
do $$
begin
  begin
    alter publication supabase_realtime add table public.assignments;
  exception when duplicate_object then null;
  end;
end $$;

-- ---------- 4. check ----------
select 'ready' as status,
       (select count(*) from public.steps where icon <> '') as icons_set,
       (select count(*) from public.assignments)             as assignments;
