# V3 Supabase — real-user acceptance tests

Use a dedicated TEST project and three independent email accounts A, B, C. Never run acceptance tests against production data. Do not put passwords, access tokens, service-role keys or database passwords in GitHub or chat.

## Setup
- [ ] Create a separate Supabase TEST project.
- [ ] Apply migrations in order: `20261110000000_v3_foundation.sql`, `20261110010000_v3_realtime.sql`, `20261110020000_v3_profile_metadata.sql`.
- [ ] Configure only the Project URL and publishable/legacy anon public key in `site/supabase-config.js`.
- [ ] Confirm Email provider and email-confirmation behavior.
- [ ] Confirm `public-media` and `private-message-media` buckets and policies exist.

## A/B/C tests
- [ ] A registers with a unique username; the selected username appears in `public.profiles`.
- [ ] B and C register independently; each has a separate Auth user and profile row.
- [ ] If email confirmation is enabled, all three confirm their own email and sign in.
- [ ] A updates own profile; B and C cannot update A's profile.
- [ ] A publishes a public pigeon post; B and C see it from separate browser/device sessions.
- [ ] A uploads an allowed image/video; the object is stored under A's UUID path in `public-media`.
- [ ] A starts a conversation with B; A and B can read/send text messages.
- [ ] C cannot list, read, or send messages in A/B's private conversation, including direct API attempts.
- [ ] Signing out removes access to authenticated profile editing and private messages.
- [ ] The result is verified across independent sessions, not merely from localStorage.

## SQL structure checks (Supabase SQL Editor)
```sql
select to_regclass('public.profiles') as profiles,
       to_regclass('public.posts') as posts,
       to_regclass('public.conversations') as conversations,
       to_regclass('public.messages') as messages;

select schemaname, tablename, rowsecurity
from pg_tables
where schemaname = 'public'
  and tablename in ('profiles','posts','post_media','conversations','conversation_members','messages')
order by tablename;

select tablename from pg_publication_tables
where pubname = 'supabase_realtime' and schemaname = 'public'
order by tablename;

select id, username, display_name from public.profiles order by created_at desc limit 10;
```

The SQL structure query does not prove RLS security. A/B/C negative-access tests are mandatory. Do not merge/deploy or migrate production users until every acceptance test passes.
