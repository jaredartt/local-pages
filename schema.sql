-- ============================================================
--  Liahona Local Pages — database schema
--  Paste the whole file into Supabase → SQL Editor → Run.
--  Safe to run more than once.
-- ============================================================

-- ---------- 1. people ----------------------------------------

-- Emails listed here become admins automatically when they sign up.
-- Add rows before your colleagues register, or tick is_admin by hand later.
create table if not exists public.allowed_emails (
  email text primary key
);

create table if not exists public.profiles (
  id          uuid primary key references auth.users on delete cascade,
  email       text,
  name        text        not null default '',
  color_index int         not null default 0,   -- 0..9, in order of joining
  is_admin    boolean     not null default false,
  created_at  timestamptz not null default now()
);

-- New sign-ups get a profile, the next colour in the rota, and admin rights
-- if their address is allow-listed. The very first account is always admin,
-- so you can never lock yourself out.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  n int;
  approved boolean;
begin
  select count(*) into n from public.profiles;
  approved := (n = 0) or exists (
    select 1 from public.allowed_emails a where lower(a.email) = lower(new.email)
  );
  insert into public.profiles (id, email, name, color_index, is_admin)
  values (
    new.id,
    new.email,
    coalesce(nullif(new.raw_user_meta_data->>'name', ''), split_part(new.email, '@', 1)),
    n % 10,
    approved
  );
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Nobody can promote themselves: only an existing admin may change
-- is_admin or color_index. Everyone may rename themselves.
--
-- auth.uid() is null when the statement comes from the SQL Editor or the
-- service key rather than from a signed-in browser. That is you, in the
-- dashboard, and it must be allowed through -- otherwise granting somebody
-- admin by hand looks like it worked and silently reverts.
create or replace function public.guard_profile_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null
     and not coalesce((select p.is_admin from public.profiles p where p.id = auth.uid()), false) then
    new.is_admin    := old.is_admin;
    new.color_index := old.color_index;
    new.email       := old.email;
  end if;
  return new;
end $$;

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard
  before update on public.profiles
  for each row execute function public.guard_profile_update();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select p.is_admin from public.profiles p where p.id = auth.uid()), false);
$$;

-- ---------- 2. structure -------------------------------------

create table if not exists public.folders (
  id    text primary key,
  name  text not null,
  color text not null default '',
  sort  int  not null default 0
);

create table if not exists public.months (
  id        text primary key,
  folder_id text not null references public.folders(id) on delete cascade,
  label     text not null,
  submitted date,
  color     text not null default '',
  sort      int  not null default 0,
  unique (folder_id, label)          -- no two Decembers in one year
);

create table if not exists public.editions (
  id    text primary key,
  name  text not null,
  code  text not null default '',
  place text not null default '',
  flag  text,
  std   boolean not null default false,   -- goes into new months automatically
  sort  int not null default 0
);

-- which editions a given month has, and in what order
create table if not exists public.month_editions (
  month_id   text not null references public.months(id)   on delete cascade,
  edition_id text not null references public.editions(id) on delete cascade,
  sort       int  not null default 0,
  primary key (month_id, edition_id)
);

create table if not exists public.phases (
  id    text primary key,
  name  text not null,
  color text not null default '',
  sort  int  not null default 0
);

create table if not exists public.steps (
  id        text primary key,
  phase_id  text not null references public.phases(id) on delete cascade,
  label     text not null,
  type      text not null default 'status',   -- 'status' | 'date'
  done_word text not null default 'Done',
  sort      int  not null default 0
);

-- ---------- 3. the tracked values ----------------------------

-- One row per month × edition × step, written only once it has a value.
-- Row-level rather than one big document, so two people moving different
-- sliders never overwrite each other.
create table if not exists public.entries (
  month_id   text not null references public.months(id)   on delete cascade,
  edition_id text not null references public.editions(id) on delete cascade,
  step_id    text not null references public.steps(id)    on delete cascade,
  progress   int,        -- 0..100 for slider steps
  on_date    date,       -- for date steps
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users,
  primary key (month_id, edition_id, step_id),
  constraint progress_range check (progress is null or (progress between 0 and 100))
);

create table if not exists public.comments (
  id          uuid primary key default gen_random_uuid(),
  month_id    text not null references public.months(id)   on delete cascade,
  edition_id  text not null references public.editions(id) on delete cascade,
  step_id     text references public.steps(id) on delete cascade,  -- null = edition note
  body        text not null,
  author      uuid references auth.users,
  author_name text not null default '',
  created_at  timestamptz not null default now()
);
create index if not exists comments_place on public.comments (month_id, edition_id, step_id);

-- ---------- 4. the log ---------------------------------------

create table if not exists public.history (
  id         bigserial primary key,
  at         timestamptz not null default now(),
  actor      uuid references auth.users,
  actor_name text not null default '',
  month_id   text,
  edition_id text,
  step_id    text,
  what       text not null,     -- "Dutch · Design & layout · 40% → 100%"
  detail     jsonb
);
create index if not exists history_at on public.history (at desc);

-- ---------- 5. who can do what -------------------------------

alter table public.allowed_emails enable row level security;
alter table public.profiles       enable row level security;
alter table public.folders        enable row level security;
alter table public.months         enable row level security;
alter table public.editions       enable row level security;
alter table public.month_editions enable row level security;
alter table public.phases         enable row level security;
alter table public.steps          enable row level security;
alter table public.entries        enable row level security;
alter table public.comments       enable row level security;
alter table public.history        enable row level security;

-- Signed in → can read everything. Approved (is_admin) → can change anything.
-- Not signed in → nothing at all.
do $$
declare t text;
begin
  foreach t in array array['folders','months','editions','month_editions',
                           'phases','steps','entries','comments','history']
  loop
    execute format('drop policy if exists read_all on public.%I', t);
    execute format('drop policy if exists write_admin on public.%I', t);
    execute format(
      'create policy read_all on public.%I for select to authenticated using (true)', t);
    execute format(
      'create policy write_admin on public.%I for all to authenticated
         using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

-- History is append-only: admins add lines, nobody edits or removes them.
drop policy if exists write_admin on public.history;
drop policy if exists history_insert on public.history;
create policy history_insert on public.history
  for insert to authenticated with check (public.is_admin());

-- Profiles: everyone signed in sees names and colours; you may rename
-- yourself (the trigger above blocks anything else); admins manage the rest.
drop policy if exists profiles_read   on public.profiles;
drop policy if exists profiles_self   on public.profiles;
drop policy if exists profiles_admin  on public.profiles;
create policy profiles_read  on public.profiles for select to authenticated using (true);
create policy profiles_self  on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_admin on public.profiles for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists allowed_admin on public.allowed_emails;
create policy allowed_admin on public.allowed_emails for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------- 6. live updates ----------------------------------

do $$
declare t text;
begin
  foreach t in array array['folders','months','editions','month_editions',
                           'phases','steps','entries','comments','history','profiles']
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ---------- 7. your admins -----------------------------------
-- Put the office addresses here so they are approved the moment they sign up.
-- Replace these two lines with the real ones, or add more.

insert into public.allowed_emails (email) values
  ('jaredartt@gmail.com')
on conflict (email) do nothing;

-- ============================================================
--  Done. Next: Authentication → Sign In / Providers → Email,
--  and turn OFF "Confirm email" so office accounts work instantly.
-- ============================================================


-- ============================================================
--  8. Starting contents — the standard structure
--     (run once; re-running changes nothing)
-- ============================================================

insert into public.phases (id, name, color, sort) values
  ('prep','Prep','yellow',0),
  ('dl','D&L','red',1),
  ('proof','Proof','purple',2),
  ('final','Final','pink',3),
  ('cc','CC','blue',4)
on conflict (id) do nothing;

insert into public.steps (id, phase_id, label, type, done_word, sort) values
  ('reminder', 'prep', 'Articles reminder',        'status','Sent',    0),
  ('remSent',  'prep', 'Reminder sent',            'date',  'Done',    1),
  ('artIn',    'prep', 'Articles coming in',       'date',  'Done',    2),
  ('sendTrans','prep', 'Sent for translation',     'status','Sent',    3),
  ('revIn',    'prep', 'Review coming in',         'date',  'Done',    4),
  ('folder',   'dl',   'Folder prep',              'status','Done',    5),
  ('ruis',     'dl',   'RUIs',                     'status','Done',    6),
  ('dl',       'dl',   'Design & layout',          'status','Designed',7),
  ('trProof',  'proof','Translator proof',         'status','Applied', 8),
  ('trProofIn','proof','TR proof coming in',       'date',  'Done',    9),
  ('edProof',  'proof','Editor proof',             'status','Applied',10),
  ('edProofIn','proof','Editor proof coming in',   'date',  'Done',   11),
  ('finalPrep','final','Final prep',               'status','Exported',12),
  ('screenSh', 'final','Export in Screen Sharing', 'status','Exported',13),
  ('finalSent','final','Final proof to editors',   'status','Sent',   14),
  ('words',    'cc',   'Update words',             'status','Updated',15),
  ('upload',   'cc',   'Upload to CC',             'status','Uploaded',16)
on conflict (id) do nothing;

-- ordered by language code, then the two sections
insert into public.editions (id, name, code, place, flag, std, sort) values
  ('bg', 'Bulgarian','112','Bulgaria',   'bg', false, 0),
  ('nl', 'Dutch',    '120','Netherlands','nl', true,  1),
  ('cs', 'Czech',    '121','Czechia',    'cz', false, 2),
  ('fr', 'French',   '140','France',     'fr', true,  3),
  ('de', 'German',   '150','Germany',    'de', true,  4),
  ('es', 'Spanish',  '178','Spain',      'es', true,  5),
  ('alm','ALM',      '',   'Area Leadership Message', null, true, 6),
  ('wel','Welfare',  '',   'Welfare article',         null, true, 7)
on conflict (id) do nothing;

insert into public.folders (id, name, color, sort) values
  ('y2026','2026','',0)
on conflict (id) do nothing;

-- one month to open onto; the six standard editions, in code order
insert into public.months (id, folder_id, label, submitted, color, sort) values
  ('m-2026-09','y2026','September', null, '', 0)
on conflict (id) do nothing;

insert into public.month_editions (month_id, edition_id, sort)
select 'm-2026-09', e.id, e.sort from public.editions e where e.std
on conflict do nothing;
