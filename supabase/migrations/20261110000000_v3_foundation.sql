-- NAXÇIVAN GÖYƏRÇİN — V3 FOUNDATION
-- Initial schema + row-level security.
-- Apply only to a NEW / reviewed Supabase project after checking its current schema.
-- This migration does not create demo users, posts, pigeons, or marketplace listings.

begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

do $$ begin
  create type public.app_role as enum (
    'moderator', 'veterinarian', 'seller', 'race_organizer', 'admin'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.post_visibility as enum ('public', 'followers', 'private');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.pigeon_visibility as enum ('public', 'private');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.pigeon_verification as enum ('unverified', 'pending', 'verified', 'rejected');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.listing_category as enum (
    'pigeon', 'feed', 'equipment', 'loft', 'transport', 'service'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.listing_status as enum (
    'draft', 'pending_review', 'active', 'sold', 'archived', 'removed'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.message_kind as enum ('text', 'image', 'video', 'system');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Private helper functions. They are not exposed as client-facing RPCs.
-- ---------------------------------------------------------------------------

create or replace function public.current_user_has_role(_role public.app_role)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles ur
    where ur.user_id = (select auth.uid())
      and ur.role = _role
  );
$$;

revoke all on function public.current_user_has_role(public.app_role) from public, anon;
-- The function checks only auth.uid(); it is safe for anonymous policy evaluation
-- and returns false when there is no authenticated user.
grant execute on function public.current_user_has_role(public.app_role) to anon, authenticated;

create or replace function public.is_conversation_member(_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id = _conversation_id
      and cm.user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_conversation_member(uuid) from public, anon;
grant execute on function public.is_conversation_member(uuid) to authenticated;

create or replace function public.is_conversation_creator(_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.conversations c
    where c.id = _conversation_id
      and c.created_by = (select auth.uid())
  );
$$;

revoke all on function public.is_conversation_creator(uuid) from public, anon;
grant execute on function public.is_conversation_creator(uuid) to authenticated;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

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
    'user_' || substr(replace(new.id::text, '-', ''), 1, 12),
    left(coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), 'New user'), 80)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function private.handle_new_auth_user() from public, anon, authenticated;

create or replace function private.protect_pigeon_verification()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Trusted SQL Editor / service-role operations may perform controlled admin work.
  if current_user in ('postgres', 'service_role', 'supabase_admin')
     or coalesce(public.current_user_has_role('admin'), false) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.platform_code := 'NG-' ||
      upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
    new.verification_status := 'unverified';
    new.verified_at := null;
    new.verified_by := null;
    return new;
  end if;

  -- Stable identifiers and creation time are immutable for non-admin updates.
  new.id := old.id;
  new.created_at := old.created_at;

  -- A moderator may change verification fields, but not pigeon ownership or identity.
  if coalesce(public.current_user_has_role('moderator'), false) then
    new.owner_id := old.owner_id;
    new.platform_code := old.platform_code;
    new.name := old.name;
    new.ring_number := old.ring_number;
    new.ring_issuer := old.ring_issuer;
    new.ring_country := old.ring_country;
    new.breed := old.breed;
    new.color := old.color;
    new.sex := old.sex;
    new.birth_date := old.birth_date;
    new.origin_country := old.origin_country;
    new.visibility := old.visibility;
    new.description := old.description;
    new.created_at := old.created_at;

    if new.verification_status = 'verified' then
      new.verified_at := now();
      new.verified_by := (select auth.uid());
    elsif new.verification_status = 'rejected' then
      new.verified_at := null;
      new.verified_by := (select auth.uid());
    else
      new.verified_at := null;
      new.verified_by := null;
    end if;
    return new;
  end if;

  -- Regular owners cannot self-verify. Editing ring/identity data invalidates
  -- a previous verification and sends the record back to pending review.
  new.platform_code := old.platform_code;
  if new.ring_number is distinct from old.ring_number
     or new.ring_issuer is distinct from old.ring_issuer
     or new.ring_country is distinct from old.ring_country
     or new.breed is distinct from old.breed
     or new.color is distinct from old.color
     or new.sex is distinct from old.sex
     or new.birth_date is distinct from old.birth_date
     or new.origin_country is distinct from old.origin_country then
    new.verification_status := 'pending';
    new.verified_at := null;
    new.verified_by := null;
  else
    new.verification_status := old.verification_status;
    new.verified_at := old.verified_at;
    new.verified_by := old.verified_by;
  end if;
  return new;
end;
$$;

create or replace function private.protect_conversation_member_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.conversation_id := old.conversation_id;
  new.user_id := old.user_id;
  new.joined_at := old.joined_at;
  return new;
end;
$$;

create or replace function private.protect_notification_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.id := old.id;
  new.user_id := old.user_id;
  new.kind := old.kind;
  new.payload := old.payload;
  new.created_at := old.created_at;
  return new;
end;
$$;

-- Message ownership and conversation membership cannot be changed by an edit.
create or replace function private.protect_message_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.id := old.id;
  new.conversation_id := old.conversation_id;
  new.sender_id := old.sender_id;
  new.kind := old.kind;
  new.created_at := old.created_at;
  return new;
end;
$$;

create or replace function private.protect_report_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not coalesce(public.current_user_has_role('admin'), false) then
    new.id := old.id;
    new.created_at := old.created_at;
    new.reporter_id := old.reporter_id;
    new.target_type := old.target_type;
    new.target_id := old.target_id;
    new.reason := old.reason;
  end if;
  return new;
end;
$$;

create or replace function private.protect_listing_moderation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('postgres', 'service_role', 'supabase_admin')
     or coalesce(public.current_user_has_role('admin'), false) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.status in ('active', 'removed') then
      new.status := 'draft';
    end if;
    return new;
  end if;

  new.id := old.id;
  new.created_at := old.created_at;

  if coalesce(public.current_user_has_role('moderator'), false) then
    -- Moderators may moderate status, not rewrite seller content or pricing.
    new.seller_id := old.seller_id;
    new.category := old.category;
    new.pigeon_id := old.pigeon_id;
    new.title := old.title;
    new.description := old.description;
    new.price := old.price;
    new.currency := old.currency;
    new.country_code := old.country_code;
    new.city := old.city;
    if new.status not in ('active', 'removed', 'pending_review', 'archived') then
      new.status := old.status;
    end if;
    return new;
  end if;

  -- Sellers may submit, sell, or archive their own listing, but cannot approve
  -- it themselves or mark it removed by moderation.
  if new.status in ('active', 'removed') then
    new.status := old.status;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Identity and authorization
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique
    check (username = lower(username)
       and username ~ '^[a-z0-9_]{3,30}$'),
  display_name text not null default 'New user'
    check (char_length(display_name) between 1 and 80),
  bio text not null default ''
    check (char_length(bio) <= 500),
  avatar_path text,
  country_code char(2),
  city text check (city is null or char_length(city) <= 100),
  locale text not null default 'az'
    check (locale in ('az', 'tr', 'en', 'ru')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_avatar_owner_path check (
    avatar_path is null or split_part(avatar_path, '/', 1) = id::text
  )
);

create table public.user_roles (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null,
  assigned_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (user_id, role)
);

create table public.follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  following_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint follows_no_self_follow check (follower_id <> following_id)
);

-- Create a basic profile automatically after Supabase Auth creates an account.
drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row execute function private.handle_new_auth_user();

-- ---------------------------------------------------------------------------
-- Social network
-- ---------------------------------------------------------------------------

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null default '' check (char_length(body) <= 10000),
  visibility public.post_visibility not null default 'public',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.post_media (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  storage_path text not null unique,
  media_type text not null check (media_type in ('image', 'video')),
  alt_text text check (alt_text is null or char_length(alt_text) <= 300),
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 3000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.reactions (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction text not null default 'like'
    check (reaction in ('like', 'love', 'support', 'interesting')),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Pigeon registry and loft records
-- ---------------------------------------------------------------------------

create table public.pigeons (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  platform_code text not null unique default (
    'NG-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))
  ),
  name text check (name is null or char_length(name) <= 80),
  ring_number text check (ring_number is null or char_length(ring_number) <= 40),
  ring_issuer text check (ring_issuer is null or char_length(ring_issuer) <= 120),
  ring_country char(2),
  breed text check (breed is null or char_length(breed) <= 120),
  color text check (color is null or char_length(color) <= 120),
  sex text not null default 'unknown' check (sex in ('male', 'female', 'unknown')),
  birth_date date,
  origin_country char(2),
  visibility public.pigeon_visibility not null default 'public',
  verification_status public.pigeon_verification not null default 'unverified',
  verified_at timestamptz,
  verified_by uuid references auth.users(id) on delete set null,
  description text not null default '' check (char_length(description) <= 5000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index pigeons_ring_identity_idx
  on public.pigeons (ring_country, ring_issuer, ring_number)
  where ring_number is not null;

create table public.pigeon_media (
  id uuid primary key default gen_random_uuid(),
  pigeon_id uuid not null references public.pigeons(id) on delete cascade,
  storage_path text not null unique,
  media_type text not null check (media_type in ('image', 'video')),
  caption text check (caption is null or char_length(caption) <= 300),
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.lofts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  description text not null default '' check (char_length(description) <= 3000),
  city text,
  country_code char(2),
  is_public boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.breeding_pairs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  loft_id uuid references public.lofts(id) on delete set null,
  male_pigeon_id uuid not null references public.pigeons(id) on delete restrict,
  female_pigeon_id uuid not null references public.pigeons(id) on delete restrict,
  started_on date,
  ended_on date,
  notes text not null default '' check (char_length(notes) <= 3000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (male_pigeon_id <> female_pigeon_id),
  check (ended_on is null or started_on is null or ended_on >= started_on)
);

-- ---------------------------------------------------------------------------
-- Marketplace
-- ---------------------------------------------------------------------------

create table public.listings (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references auth.users(id) on delete cascade,
  category public.listing_category not null,
  pigeon_id uuid references public.pigeons(id) on delete set null,
  title text not null check (char_length(title) between 3 and 160),
  description text not null default '' check (char_length(description) <= 8000),
  price numeric(12,2) check (price is null or price >= 0),
  currency char(3) not null default 'AZN'
    check (currency ~ '^[A-Z]{3}$'),
  country_code char(2),
  city text,
  status public.listing_status not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.listing_media (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  storage_path text not null unique,
  media_type text not null check (media_type in ('image', 'video')),
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Direct messaging
-- ---------------------------------------------------------------------------

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id) on delete cascade,
  title text check (title is null or char_length(title) <= 120),
  is_group boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  last_read_at timestamptz,
  primary key (conversation_id, user_id)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  kind public.message_kind not null default 'text',
  body text not null default '' check (char_length(body) <= 10000),
  media_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (char_length(body) > 0 or media_path is not null or kind = 'system')
);

-- ---------------------------------------------------------------------------
-- Reports and moderation audit
-- ---------------------------------------------------------------------------

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  target_type text not null
    check (target_type in ('user', 'post', 'comment', 'pigeon', 'listing', 'message')),
  target_id uuid not null,
  reason text not null check (char_length(reason) between 3 and 1000),
  status text not null default 'open'
    check (status in ('open', 'reviewing', 'resolved', 'rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.moderation_actions (
  id uuid primary key default gen_random_uuid(),
  moderator_id uuid not null references auth.users(id) on delete restrict,
  target_type text not null,
  target_id uuid not null,
  action text not null
    check (action in ('warn', 'hide', 'restore', 'remove', 'suspend', 'verify', 'reject_verification')),
  reason text not null check (char_length(reason) between 3 and 2000),
  created_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (char_length(kind) between 1 and 80),
  payload jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at before update on public.profiles
for each row execute function private.set_updated_at();

drop trigger if exists posts_updated_at on public.posts;
create trigger posts_updated_at before update on public.posts
for each row execute function private.set_updated_at();

drop trigger if exists comments_updated_at on public.comments;
create trigger comments_updated_at before update on public.comments
for each row execute function private.set_updated_at();

drop trigger if exists pigeons_updated_at on public.pigeons;
create trigger pigeons_updated_at before update on public.pigeons
for each row execute function private.set_updated_at();

drop trigger if exists pigeons_verification_guard on public.pigeons;
create trigger pigeons_verification_guard before insert or update on public.pigeons
for each row execute function private.protect_pigeon_verification();

drop trigger if exists lofts_updated_at on public.lofts;
create trigger lofts_updated_at before update on public.lofts
for each row execute function private.set_updated_at();

drop trigger if exists breeding_pairs_updated_at on public.breeding_pairs;
create trigger breeding_pairs_updated_at before update on public.breeding_pairs
for each row execute function private.set_updated_at();

drop trigger if exists listings_updated_at on public.listings;
create trigger listings_updated_at before update on public.listings
for each row execute function private.set_updated_at();

drop trigger if exists listings_moderation_guard on public.listings;
create trigger listings_moderation_guard before insert or update on public.listings
for each row execute function private.protect_listing_moderation();

drop trigger if exists conversations_updated_at on public.conversations;
create trigger conversations_updated_at before update on public.conversations
for each row execute function private.set_updated_at();

drop trigger if exists messages_identity_guard on public.messages;
create trigger messages_identity_guard before update on public.messages
for each row execute function private.protect_message_identity();

drop trigger if exists messages_updated_at on public.messages;
create trigger messages_updated_at before update on public.messages
for each row execute function private.set_updated_at();

drop trigger if exists reports_updated_at on public.reports;
create trigger reports_updated_at before update on public.reports
for each row execute function private.set_updated_at();

drop trigger if exists reports_identity_guard on public.reports;
create trigger reports_identity_guard before update on public.reports
for each row execute function private.protect_report_identity();

drop trigger if exists conversation_members_update_guard on public.conversation_members;
create trigger conversation_members_update_guard before update on public.conversation_members
for each row execute function private.protect_conversation_member_update();

drop trigger if exists notifications_update_guard on public.notifications;
create trigger notifications_update_guard before update on public.notifications
for each row execute function private.protect_notification_update();

-- ---------------------------------------------------------------------------
-- Indexes used by common lookups and RLS predicates
-- ---------------------------------------------------------------------------

create index profiles_username_idx on public.profiles (username);
create index user_roles_user_id_idx on public.user_roles (user_id);
create index follows_following_id_idx on public.follows (following_id);
create index posts_author_created_idx on public.posts (author_id, created_at desc);
create index posts_visibility_created_idx on public.posts (visibility, created_at desc);
create index comments_post_created_idx on public.comments (post_id, created_at);
create index pigeons_owner_created_idx on public.pigeons (owner_id, created_at desc);
create index pigeons_visibility_idx on public.pigeons (visibility);
create index pigeon_media_pigeon_idx on public.pigeon_media (pigeon_id, sort_order);
create index lofts_owner_idx on public.lofts (owner_id);
create index breeding_pairs_owner_idx on public.breeding_pairs (owner_id);
create index listings_status_created_idx on public.listings (status, created_at desc);
create index listings_seller_idx on public.listings (seller_id);
create index listing_media_listing_idx on public.listing_media (listing_id, sort_order);
create index conversation_members_user_idx on public.conversation_members (user_id);
create index messages_conversation_created_idx on public.messages (conversation_id, created_at);
create index reports_status_created_idx on public.reports (status, created_at);
create index notifications_user_created_idx on public.notifications (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Enable RLS everywhere
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.follows enable row level security;
alter table public.posts enable row level security;
alter table public.post_media enable row level security;
alter table public.comments enable row level security;
alter table public.reactions enable row level security;
alter table public.pigeons enable row level security;
alter table public.pigeon_media enable row level security;
alter table public.lofts enable row level security;
alter table public.breeding_pairs enable row level security;
alter table public.listings enable row level security;
alter table public.listing_media enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.reports enable row level security;
alter table public.moderation_actions enable row level security;
alter table public.notifications enable row level security;

-- Profiles: public read; only the owner edits their profile.
create policy profiles_public_read on public.profiles
for select to anon, authenticated using (true);
create policy profiles_owner_update on public.profiles
for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

-- Roles: users can see their own assigned roles; no client-side role writes.
create policy user_roles_self_or_admin_read on public.user_roles
for select to authenticated
using (
  user_id = (select auth.uid())
  or public.current_user_has_role('admin')
);

-- Follows: public relationship graph; users create/delete only their own follow edge.
create policy follows_public_read on public.follows
for select to anon, authenticated using (true);
create policy follows_insert_self on public.follows
for insert to authenticated
with check (follower_id = (select auth.uid()) and following_id <> (select auth.uid()));
create policy follows_delete_self on public.follows
for delete to authenticated
using (follower_id = (select auth.uid()));

-- Posts: public posts, followed accounts' posts, or own posts.
create policy posts_read_visible on public.posts
for select to anon, authenticated
using (
  visibility = 'public'
  or author_id = (select auth.uid())
  or (
    visibility = 'followers'
    and exists (
      select 1 from public.follows f
      where f.follower_id = (select auth.uid())
        and f.following_id = posts.author_id
    )
  )
  or public.current_user_has_role('moderator')
  or public.current_user_has_role('admin')
);
create policy posts_insert_own on public.posts
for insert to authenticated
with check (author_id = (select auth.uid()));
create policy posts_update_own_or_admin on public.posts
for update to authenticated
using (
  author_id = (select auth.uid())
  or public.current_user_has_role('admin')
)
with check (
  author_id = (select auth.uid())
  or public.current_user_has_role('admin')
);
create policy posts_delete_own_or_moderator on public.posts
for delete to authenticated
using (
  author_id = (select auth.uid())
  or public.current_user_has_role('moderator')
  or public.current_user_has_role('admin')
);

-- Post media inherits access from its parent post.
create policy post_media_read_with_post on public.post_media
for select to anon, authenticated
using (exists (select 1 from public.posts p where p.id = post_id));
create policy post_media_insert_own_post on public.post_media
for insert to authenticated
with check (
  exists (
    select 1 from public.posts p
    where p.id = post_id and p.author_id = (select auth.uid())
  )
  and split_part(storage_path, '/', 1) = (select auth.uid())::text
);
create policy post_media_delete_own_post on public.post_media
for delete to authenticated
using (
  exists (
    select 1 from public.posts p
    where p.id = post_id and p.author_id = (select auth.uid())
  )
  or public.current_user_has_role('admin')
);

-- Comments and reactions: only on posts visible to the requesting user.
create policy comments_read_visible_post on public.comments
for select to anon, authenticated
using (exists (select 1 from public.posts p where p.id = post_id));
create policy comments_insert_visible_post on public.comments
for insert to authenticated
with check (
  author_id = (select auth.uid())
  and exists (select 1 from public.posts p where p.id = post_id)
);
create policy comments_update_own_or_admin on public.comments
for update to authenticated
using (
  author_id = (select auth.uid())
  or public.current_user_has_role('admin')
)
with check (
  (
    author_id = (select auth.uid())
    and exists (select 1 from public.posts p where p.id = post_id)
  )
  or public.current_user_has_role('admin')
);
create policy comments_delete_own_or_moderator on public.comments
for delete to authenticated
using (
  author_id = (select auth.uid())
  or public.current_user_has_role('moderator')
  or public.current_user_has_role('admin')
);

create policy reactions_read_visible_post on public.reactions
for select to anon, authenticated
using (exists (select 1 from public.posts p where p.id = post_id));
create policy reactions_insert_self_visible_post on public.reactions
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and exists (select 1 from public.posts p where p.id = post_id)
);
create policy reactions_delete_self on public.reactions
for delete to authenticated
using (user_id = (select auth.uid()));

-- Pigeon records: public profiles or owner; verification fields are trigger-protected.
create policy pigeons_read_public_or_owner on public.pigeons
for select to anon, authenticated
using (
  visibility = 'public'
  or owner_id = (select auth.uid())
  or public.current_user_has_role('moderator')
  or public.current_user_has_role('admin')
);
create policy pigeons_insert_owner on public.pigeons
for insert to authenticated
with check (owner_id = (select auth.uid()));
create policy pigeons_update_owner_or_moderator_or_admin on public.pigeons
for update to authenticated
using (
  owner_id = (select auth.uid())
  or public.current_user_has_role('moderator')
  or public.current_user_has_role('admin')
)
with check (
  owner_id = (select auth.uid())
  or public.current_user_has_role('moderator')
  or public.current_user_has_role('admin')
);
create policy pigeons_delete_owner_or_admin on public.pigeons
for delete to authenticated
using (owner_id = (select auth.uid()) or public.current_user_has_role('admin'));

create policy pigeon_media_read_accessible_pigeon on public.pigeon_media
for select to anon, authenticated
using (exists (select 1 from public.pigeons p where p.id = pigeon_id));
create policy pigeon_media_insert_owner on public.pigeon_media
for insert to authenticated
with check (
  exists (
    select 1 from public.pigeons p
    where p.id = pigeon_id and p.owner_id = (select auth.uid())
  )
  and split_part(storage_path, '/', 1) = (select auth.uid())::text
);
create policy pigeon_media_delete_owner_or_admin on public.pigeon_media
for delete to authenticated
using (
  exists (
    select 1 from public.pigeons p
    where p.id = pigeon_id and p.owner_id = (select auth.uid())
  )
  or public.current_user_has_role('admin')
);

-- Lofts and breeding data are private to their owner unless a loft is public.
create policy lofts_read_public_or_owner on public.lofts
for select to anon, authenticated
using (is_public or owner_id = (select auth.uid()));
create policy lofts_insert_owner on public.lofts
for insert to authenticated with check (owner_id = (select auth.uid()));
create policy lofts_update_owner on public.lofts
for update to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));
create policy lofts_delete_owner on public.lofts
for delete to authenticated using (owner_id = (select auth.uid()));

create policy breeding_pairs_owner_all on public.breeding_pairs
for all to authenticated
using (owner_id = (select auth.uid()))
with check (
  owner_id = (select auth.uid())
  and exists (
    select 1 from public.pigeons p
    where p.id = male_pigeon_id and p.owner_id = (select auth.uid())
  )
  and exists (
    select 1 from public.pigeons p
    where p.id = female_pigeon_id and p.owner_id = (select auth.uid())
  )
  and (
    loft_id is null
    or exists (
      select 1 from public.lofts l
      where l.id = loft_id and l.owner_id = (select auth.uid())
    )
  )
);

-- Marketplace: only active listings are public. Seller owns draft/submission lifecycle.
create policy listings_read_active_or_owner on public.listings
for select to anon, authenticated
using (
  status = 'active'
  or seller_id = (select auth.uid())
  or public.current_user_has_role('moderator')
  or public.current_user_has_role('admin')
);
create policy listings_insert_seller_draft on public.listings
for insert to authenticated
with check (
  seller_id = (select auth.uid())
  and status in ('draft', 'pending_review')
  and (
    pigeon_id is null
    or exists (
      select 1 from public.pigeons p
      where p.id = pigeon_id and p.owner_id = (select auth.uid())
    )
  )
);
create policy listings_update_seller_or_moderator_or_admin on public.listings
for update to authenticated
using (
  seller_id = (select auth.uid())
  or public.current_user_has_role('moderator')
  or public.current_user_has_role('admin')
)
with check (
  (
    seller_id = (select auth.uid())
    and (
      pigeon_id is null
      or exists (
        select 1 from public.pigeons p
        where p.id = pigeon_id and p.owner_id = (select auth.uid())
      )
    )
  )
  or public.current_user_has_role('moderator')
  or public.current_user_has_role('admin')
);
create policy listings_delete_seller_or_admin on public.listings
for delete to authenticated
using (seller_id = (select auth.uid()) or public.current_user_has_role('admin'));

create policy listing_media_read_visible_listing on public.listing_media
for select to anon, authenticated
using (exists (select 1 from public.listings l where l.id = listing_id));
create policy listing_media_insert_seller on public.listing_media
for insert to authenticated
with check (
  exists (
    select 1 from public.listings l
    where l.id = listing_id and l.seller_id = (select auth.uid())
  )
  and split_part(storage_path, '/', 1) = (select auth.uid())::text
);
create policy listing_media_delete_seller_or_admin on public.listing_media
for delete to authenticated
using (
  exists (
    select 1 from public.listings l
    where l.id = listing_id and l.seller_id = (select auth.uid())
  )
  or public.current_user_has_role('admin')
);

-- Conversations: membership is checked through SECURITY DEFINER helper functions
-- to avoid recursive RLS policy evaluation on conversation_members.
create policy conversations_member_read on public.conversations
for select to authenticated
using (
  public.is_conversation_member(id)
  or created_by = (select auth.uid())
  or public.current_user_has_role('admin')
);
create policy conversations_create_self on public.conversations
for insert to authenticated
with check (created_by = (select auth.uid()));
create policy conversations_creator_update on public.conversations
for update to authenticated
using (created_by = (select auth.uid()) or public.current_user_has_role('admin'))
with check (created_by = (select auth.uid()) or public.current_user_has_role('admin'));
create policy conversations_creator_delete on public.conversations
for delete to authenticated
using (created_by = (select auth.uid()) or public.current_user_has_role('admin'));

create policy conversation_members_read_member on public.conversation_members
for select to authenticated
using (
  user_id = (select auth.uid())
  or public.is_conversation_member(conversation_id)
  or public.current_user_has_role('admin')
);
create policy conversation_members_add_by_creator on public.conversation_members
for insert to authenticated
with check (
  public.is_conversation_creator(conversation_id)
  or public.current_user_has_role('admin')
);
create policy conversation_members_leave_or_creator_remove on public.conversation_members
for delete to authenticated
using (
  user_id = (select auth.uid())
  or public.is_conversation_creator(conversation_id)
  or public.current_user_has_role('admin')
);

create policy conversation_members_update_read_receipt on public.conversation_members
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy messages_read_member on public.messages
for select to authenticated
using (
  public.is_conversation_member(conversation_id)
  or public.current_user_has_role('admin')
);
create policy messages_insert_member_self on public.messages
for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and public.is_conversation_member(conversation_id)
  and kind <> 'system'
);
create policy messages_update_own on public.messages
for update to authenticated
using (sender_id = (select auth.uid()) and public.is_conversation_member(conversation_id))
with check (
  sender_id = (select auth.uid())
  and public.is_conversation_member(conversation_id)
  and kind <> 'system'
);
create policy messages_delete_own_or_admin on public.messages
for delete to authenticated
using (
  sender_id = (select auth.uid())
  or public.current_user_has_role('admin')
);

-- Reports: reporters can create and see their own reports; moderators/admins review.
create policy reports_insert_self on public.reports
for insert to authenticated
with check (reporter_id = (select auth.uid()));
create policy reports_read_self_or_moderator on public.reports
for select to authenticated
using (
  reporter_id = (select auth.uid())
  or public.current_user_has_role('moderator')
  or public.current_user_has_role('admin')
);
create policy reports_update_moderator on public.reports
for update to authenticated
using (
  public.current_user_has_role('moderator')
  or public.current_user_has_role('admin')
)
with check (
  public.current_user_has_role('moderator')
  or public.current_user_has_role('admin')
);

create policy moderation_actions_admin_read on public.moderation_actions
for select to authenticated
using (
  public.current_user_has_role('moderator')
  or public.current_user_has_role('admin')
);
create policy moderation_actions_admin_insert on public.moderation_actions
for insert to authenticated
with check (
  moderator_id = (select auth.uid())
  and (
    public.current_user_has_role('moderator')
    or public.current_user_has_role('admin')
  )
);

create policy notifications_owner_read on public.notifications
for select to authenticated using (user_id = (select auth.uid()));
create policy notifications_owner_update on public.notifications
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Grants. RLS still decides which rows are accessible.
-- ---------------------------------------------------------------------------

grant usage on schema public to anon, authenticated;

grant select on public.profiles, public.follows, public.posts, public.post_media,
  public.comments, public.reactions, public.pigeons, public.pigeon_media,
  public.lofts, public.listings, public.listing_media to anon, authenticated;

grant select, update on public.profiles to authenticated;
grant select on public.user_roles to authenticated;
grant select, insert, delete on public.follows to authenticated;
grant select, insert, update, delete on public.posts to authenticated;
grant select, insert, delete on public.post_media to authenticated;
grant select, insert, update, delete on public.comments to authenticated;
grant select, insert, delete on public.reactions to authenticated;
grant select, insert, update, delete on public.pigeons to authenticated;
grant select, insert, delete on public.pigeon_media to authenticated;
grant select, insert, update, delete on public.lofts to authenticated;
grant select, insert, update, delete on public.breeding_pairs to authenticated;
grant select, insert, update, delete on public.listings to authenticated;
grant select, insert, delete on public.listing_media to authenticated;
grant select, insert, update, delete on public.conversations to authenticated;
grant select, insert, update, delete on public.conversation_members to authenticated;
grant select, insert, update, delete on public.messages to authenticated;
grant select, insert, update on public.reports to authenticated;
grant select, insert on public.moderation_actions to authenticated;
grant select, update on public.notifications to authenticated;

grant usage, select on all sequences in schema public to authenticated;

-- ---------------------------------------------------------------------------
-- Public media bucket. Public reads are intentional for public social content.
-- The bucket is named public-media; the object key starts with <auth.uid()>.
-- Do not upload private documents, chat attachments, or sensitive veterinary
-- records here.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'public-media',
  'public-media',
  true,
  104857600,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/webm']
)
on conflict (id) do nothing;

drop policy if exists public_media_insert_own_folder on storage.objects;
create policy public_media_insert_own_folder on storage.objects
for insert to authenticated
with check (
  bucket_id = 'public-media'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists public_media_update_own_folder on storage.objects;
create policy public_media_update_own_folder on storage.objects
for update to authenticated
using (
  bucket_id = 'public-media'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or public.current_user_has_role('admin')
  )
)
with check (
  bucket_id = 'public-media'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or public.current_user_has_role('admin')
  )
);

drop policy if exists public_media_delete_own_folder on storage.objects;
create policy public_media_delete_own_folder on storage.objects
for delete to authenticated
using (
  bucket_id = 'public-media'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or public.current_user_has_role('admin')
  )
);

-- ---------------------------------------------------------------------------
-- Private message media. Object key:
-- <conversation_uuid>/<uploader_auth_uid>/<filename>
-- Only authenticated conversation members can read attachments. Upload,
-- update, and delete are restricted to the uploader's own folder.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'private-message-media',
  'private-message-media',
  false,
  52428800,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/webm']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists private_message_media_select_member on storage.objects;
create policy private_message_media_select_member on storage.objects
for select to authenticated
using (
  bucket_id = 'private-message-media'
  and public.is_conversation_member(((storage.foldername(name))[1])::uuid)
);

drop policy if exists private_message_media_insert_member_own_folder on storage.objects;
create policy private_message_media_insert_member_own_folder on storage.objects
for insert to authenticated
with check (
  bucket_id = 'private-message-media'
  and (storage.foldername(name))[2] = (select auth.uid())::text
  and public.is_conversation_member(((storage.foldername(name))[1])::uuid)
);

drop policy if exists private_message_media_update_member_own_folder on storage.objects;
create policy private_message_media_update_member_own_folder on storage.objects
for update to authenticated
using (
  bucket_id = 'private-message-media'
  and (storage.foldername(name))[2] = (select auth.uid())::text
  and public.is_conversation_member(((storage.foldername(name))[1])::uuid)
)
with check (
  bucket_id = 'private-message-media'
  and (storage.foldername(name))[2] = (select auth.uid())::text
  and public.is_conversation_member(((storage.foldername(name))[1])::uuid)
);

drop policy if exists private_message_media_delete_member_own_folder on storage.objects;
create policy private_message_media_delete_member_own_folder on storage.objects
for delete to authenticated
using (
  bucket_id = 'private-message-media'
  and (storage.foldername(name))[2] = (select auth.uid())::text
  and public.is_conversation_member(((storage.foldername(name))[1])::uuid)
);

commit;
