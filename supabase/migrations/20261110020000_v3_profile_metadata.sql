-- NAXÇIVAN GÖYƏRÇİN V3 — persist signup username from Auth metadata
-- Apply after 20261110000000_v3_foundation.sql and 20261110010000_v3_realtime.sql.
-- Existing profile rows are not rewritten.

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    case
      when coalesce(new.raw_user_meta_data ->> 'username', '') ~ '^[a-z0-9_]{3,30}$'
        then new.raw_user_meta_data ->> 'username'
      else 'user_' || substr(replace(new.id::text, '-', ''), 1, 12)
    end,
    left(coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), 'New user'), 80)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function private.handle_new_auth_user() from public, anon, authenticated;
