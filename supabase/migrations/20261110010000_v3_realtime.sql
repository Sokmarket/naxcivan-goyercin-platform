-- NAXÇIVAN GÖYƏRÇİN V3 — Realtime publication
-- Apply only AFTER 20261110000000_v3_foundation.sql.
-- Realtime is an update channel, not an authorization layer; RLS remains mandatory.

do $$
declare
  tbl text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach tbl in array array[
      'posts',
      'post_media',
      'comments',
      'reactions',
      'messages',
      'conversation_members',
      'notifications'
    ]
    loop
      if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = tbl
      ) then
        execute format('alter publication supabase_realtime add table public.%I', tbl);
      end if;
    end loop;
  else
    raise notice 'supabase_realtime publication does not exist; enable Supabase Realtime before using live updates.';
  end if;
end
$$;
