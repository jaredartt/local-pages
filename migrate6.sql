-- ============================================================
--  Local Pages — per-page (section) icon + colour
--  Paste the whole file into Supabase → SQL Editor → Run.
--  Safe to run more than once.
-- ============================================================

-- One row per top-level page: 'local', 'magazines', 'design', 'team'.
-- icon is a Material Symbols name (same picker as step icons), or ''
-- to fall back to that page's original built-in glyph. icon_color is
-- one of the COLORS ids ("red"/"orange"/.../"grey"), or '' for the
-- default muted tone.
create table if not exists public.sections (
  id         text primary key,
  icon       text not null default '',
  icon_color text not null default '',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users
);

alter table public.sections enable row level security;

drop policy if exists read_all    on public.sections;
drop policy if exists write_admin on public.sections;
create policy read_all    on public.sections for select to authenticated using (true);
create policy write_admin on public.sections for all    to authenticated
  using (public.is_admin()) with check (public.is_admin());

do $$
begin
  begin
    alter publication supabase_realtime add table public.sections;
  exception when duplicate_object then null;
  end;
end $$;

select 'ready' as status, (select count(*) from public.sections) as sections;
