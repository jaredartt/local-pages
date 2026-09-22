-- ============================================================
--  Local Pages — user colours, multi-assignee steps, calendar
--  scheduling fields, and the new unified "tasks" table (Extra
--  page + Team calendar).
--  Paste the whole file into Supabase → SQL Editor → Run.
--  Applied live via the Supabase MCP connector on 22 Sep 2026;
--  kept here as the durable, readable record (see CLAUDE_NOTES.md).
-- ============================================================

-- ---------- 1. per-user identity colour ----------
-- One of: red / blue / orange / green / brown / purple / skyblue.
-- '' (the default) means "no explicit colour yet" -- the app falls
-- back to the existing color_index rotation until the person picks one.
alter table public.profiles
  add column if not exists color text not null default '';

-- ---------- 2. multi-assignee steps ----------
-- Was one row per (month, edition, step) with a single user_id. Now a
-- proper join table: any number of rows per cell, one per assignee.
-- Also gained cal_date / start_time / end_time so an assigned step can
-- optionally be placed on the Team calendar (nulls = not scheduled).
-- If you're running this by hand and any existing row has a null
-- user_id, delete those rows first -- the NOT NULL below will fail
-- otherwise. (Production had none.)
alter table public.assignments alter column user_id set not null;
alter table public.assignments drop constraint if exists assignments_user_id_fkey;
alter table public.assignments add constraint assignments_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.assignments drop constraint if exists assignments_pkey;
alter table public.assignments add primary key (month_id, edition_id, step_id, user_id);

alter table public.assignments add column if not exists cal_date   date;
alter table public.assignments add column if not exists start_time text;
alter table public.assignments add column if not exists end_time   text;

-- ---------- 3. tasks (the "Extra" page + anything on the calendar
--              that isn't a Local Pages grid step). Round 4's
--              member_tasks/member_steps tables are left in place
--              (still 0 rows in production) but the app stops using
--              them -- drop them by hand later if you want. ----------
create table if not exists public.tasks (
  id         text primary key,
  title      text not null,
  category   text not null default 'extra',
  notes      text not null default '',
  status     text not null default 'todo',
  cal_date   date,
  start_time text,
  end_time   text,
  color      text not null default '',
  sort       integer not null default 0,
  created_by uuid references auth.users on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users on delete set null
);

create table if not exists public.task_assignees (
  task_id text not null references public.tasks(id) on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  primary key (task_id, user_id)
);
create index if not exists task_assignees_user on public.task_assignees (user_id);

alter table public.tasks           enable row level security;
alter table public.task_assignees  enable row level security;

drop policy if exists read_all    on public.tasks;
drop policy if exists write_admin on public.tasks;
create policy read_all    on public.tasks for select to authenticated using (true);
create policy write_admin on public.tasks for all    to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists read_all    on public.task_assignees;
drop policy if exists write_admin on public.task_assignees;
create policy read_all    on public.task_assignees for select to authenticated using (true);
create policy write_admin on public.task_assignees for all    to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------- 4. comments, generalised to also hang off a task ----------
-- A comment now belongs to EITHER a Local Pages grid step (month_id +
-- edition_id, step_id optional) OR a standalone task (task_id) -- so
-- month_id/edition_id have to stop being required.
alter table public.comments add column if not exists task_id text references public.tasks(id) on delete cascade;
alter table public.comments alter column month_id   drop not null;
alter table public.comments alter column edition_id drop not null;
create index if not exists comments_task on public.comments (task_id);

-- ---------- 5. live updates ----------
do $$
begin
  begin alter publication supabase_realtime add table public.tasks;           exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.task_assignees;  exception when duplicate_object then null; end;
end $$;

-- ---------- 6. check ----------
select 'ready' as status,
       (select count(*) from public.assignments)     as assignments,
       (select count(*) from public.tasks)            as tasks,
       (select count(*) from public.task_assignees)   as task_assignees;
