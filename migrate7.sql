-- ============================================================
--  Local Pages — independent per-member tasks (Team page)
--  Paste the whole file into Supabase → SQL Editor → Run.
--  Safe to run more than once.
-- ============================================================

-- A phase-like group of customizable steps, scoped to one team member
-- and independent of any folder/month/edition. Nothing here is shared
-- with the main grid.
create table if not exists public.member_tasks (
  id         text primary key,
  user_id    uuid not null references auth.users,
  name       text not null,
  color      text not null default '',
  sort       integer not null default 0,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users
);

-- A step inside one member_tasks group. type is 'status' (0-100 slider,
-- stored in progress) or 'date' (stored in date_value). icon is a
-- Material Symbols name, or '' for none -- no per-step colour, matching
-- the main grid's steps.
create table if not exists public.member_steps (
  id         text primary key,
  task_id    text not null references public.member_tasks(id) on delete cascade,
  label      text not null,
  type       text not null default 'status',
  done_word  text not null default 'Done',
  icon       text not null default '',
  progress   integer not null default 0,
  date_value text not null default '',
  sort       integer not null default 0,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users
);

alter table public.member_tasks enable row level security;
alter table public.member_steps enable row level security;

drop policy if exists read_all    on public.member_tasks;
drop policy if exists write_admin on public.member_tasks;
create policy read_all    on public.member_tasks for select to authenticated using (true);
create policy write_admin on public.member_tasks for all    to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists read_all    on public.member_steps;
drop policy if exists write_admin on public.member_steps;
create policy read_all    on public.member_steps for select to authenticated using (true);
create policy write_admin on public.member_steps for all    to authenticated
  using (public.is_admin()) with check (public.is_admin());

do $$
begin
  begin
    alter publication supabase_realtime add table public.member_tasks;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.member_steps;
  exception when duplicate_object then null;
  end;
end $$;

select 'ready' as status,
  (select count(*) from public.member_tasks) as member_tasks,
  (select count(*) from public.member_steps) as member_steps;
