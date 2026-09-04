-- ============================================================
--  Local Pages — replies and notifications
--  Paste the whole file into Supabase → SQL Editor → Run.
--  Safe to run more than once.
-- ============================================================

-- ---------- 1. replies ----------
-- A comment may hang off another comment. One level is all the app
-- shows, but the column allows deeper if that ever changes. Deleting a
-- comment takes its replies with it.
alter table public.comments
  add column if not exists parent_id uuid references public.comments(id) on delete cascade;

create index if not exists comments_parent on public.comments (parent_id);

-- ---------- 2. notifications ----------
-- One row per person who needs to be told something. It carries where
-- it points, so clicking it can open that exact step.
create table if not exists public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users on delete cascade,  -- who is being told
  actor       uuid references auth.users,                             -- who caused it
  actor_name  text not null default '',
  kind        text not null default 'reply',
  month_id    text,
  edition_id  text,
  step_id     text,
  comment_id  uuid references public.comments(id) on delete cascade,
  preview     text not null default '',
  created_at  timestamptz not null default now(),
  read_at     timestamptz
);

create index if not exists notif_for  on public.notifications (user_id, created_at desc);
create index if not exists notif_open on public.notifications (user_id) where read_at is null;

alter table public.notifications enable row level security;

-- You only ever see your own, and only you can mark them read.
-- Anyone signed in may leave one for somebody else, but only stamped
-- with their own name -- you cannot forge a notification from a colleague.
drop policy if exists notif_read   on public.notifications;
drop policy if exists notif_write  on public.notifications;
drop policy if exists notif_mine   on public.notifications;
create policy notif_read on public.notifications
  for select to authenticated using (user_id = auth.uid());
create policy notif_write on public.notifications
  for insert to authenticated with check (actor = auth.uid());
create policy notif_mine on public.notifications
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- 3. live updates ----------
do $$
begin
  begin
    alter publication supabase_realtime add table public.notifications;
  exception when duplicate_object then null;
  end;
end $$;

-- ---------- 4. check ----------
select 'ready' as status,
       (select count(*) from public.comments)      as comments,
       (select count(*) from public.notifications) as notifications;
