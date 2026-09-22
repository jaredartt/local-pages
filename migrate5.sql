-- ============================================================
--  Local Pages — step icon colour
--  Paste the whole file into Supabase → SQL Editor → Run.
--  Safe to run more than once.
-- ============================================================

-- A COLORS id (red/orange/yellow/green/teal/blue/purple/pink/grey), or ''
-- to use the default muted tone -- same colour set already used for
-- phases, months and folders.
alter table public.steps
  add column if not exists icon_color text not null default '';

select 'ready' as status,
       (select count(*) from public.steps where icon_color <> '') as coloured_icons;
