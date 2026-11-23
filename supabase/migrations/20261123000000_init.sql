-- Nightshift schema, authorization, storage, and moderation hooks.
-- Apply in the Supabase SQL editor or with the Supabase CLI.
-- The app uses the anon key only. Never ship the service role key.

create extension if not exists pgcrypto;

do $$ begin
  create type public.event_category as enum ('meet', 'jdm', 'euro', 'classic', 'track', 'coffee', 'show');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.event_visibility as enum ('public', 'private');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.event_status as enum ('scheduled', 'cancelled');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.report_target as enum ('post', 'comment', 'event', 'profile', 'vehicle');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.notification_type as enum ('follow', 'like', 'comment', 'event_join', 'vehicle_comment');
exception when duplicate_object then null;
end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique,
  display_name text not null,
  avatar_url text,
  cover_url text,
  bio text not null default '',
  home_city text,
  show_garage boolean not null default true,
  show_city boolean not null default true,
  created_at timestamptz not null default now(),
  constraint username_format check (username ~ '^[a-z0-9_]{3,20}$'),
  constraint bio_length check (char_length(bio) <= 280),
  constraint display_name_length check (char_length(display_name) between 1 and 40)
);

create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  make text not null,
  model text not null,
  year integer not null check (year between 1900 and 2100),
  trim text,
  color text,
  body_style text,
  transmission text,
  engine text,
  power text,
  nickname text,
  description text not null default '',
  created_at timestamptz not null default now(),
  constraint vehicle_make_length check (char_length(make) between 1 and 40),
  constraint vehicle_model_length check (char_length(model) between 1 and 40),
  constraint vehicle_description_length check (char_length(description) <= 2000)
);

create index if not exists vehicles_owner_idx on public.vehicles (owner_id, created_at desc);

create table if not exists public.vehicle_photos (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  storage_path text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists vehicle_photos_order_idx on public.vehicle_photos (vehicle_id, sort_order);

create table if not exists public.vehicle_modifications (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  category text not null,
  name text not null,
  description text not null default '',
  constraint mod_name_length check (char_length(name) between 1 and 80)
);

create index if not exists vehicle_mods_idx on public.vehicle_modifications (vehicle_id);

create table if not exists public.vehicle_likes (
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (vehicle_id, user_id)
);

create table if not exists public.vehicle_comments (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now(),
  hidden boolean not null default false,
  constraint vehicle_comment_length check (char_length(content) between 1 and 2000)
);

create index if not exists vehicle_comments_idx on public.vehicle_comments (vehicle_id, created_at);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  description text not null,
  rules text not null default '',
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  address text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  category public.event_category not null,
  capacity integer,
  visibility public.event_visibility not null default 'public',
  cover_image_path text,
  status public.event_status not null default 'scheduled',
  created_at timestamptz not null default now(),
  constraint event_title_length check (char_length(title) between 3 and 80),
  constraint event_description_length check (char_length(description) between 10 and 4000),
  constraint event_address_length check (char_length(address) between 3 and 160),
  constraint event_time_order check (ends_at > starts_at),
  constraint event_capacity check (capacity is null or capacity between 2 and 5000)
);

create index if not exists events_discovery_idx on public.events (status, visibility, starts_at);
create index if not exists events_host_idx on public.events (host_id, starts_at desc);
create index if not exists events_geo_idx on public.events (latitude, longitude);

create table if not exists public.event_attendees (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  vehicle_id uuid references public.vehicles (id) on delete set null,
  joined_at timestamptz not null default now(),
  unique (event_id, user_id)
);

create index if not exists event_attendees_event_idx on public.event_attendees (event_id);
create index if not exists event_attendees_user_idx on public.event_attendees (user_id);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  vehicle_id uuid references public.vehicles (id) on delete set null,
  caption text not null default '',
  created_at timestamptz not null default now(),
  hidden boolean not null default false,
  constraint post_caption_length check (char_length(caption) <= 2000)
);

create index if not exists posts_created_idx on public.posts (created_at desc);
create index if not exists posts_author_idx on public.posts (author_id, created_at desc);

create table if not exists public.post_images (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  storage_path text not null,
  sort_order integer not null default 0
);

create index if not exists post_images_idx on public.post_images (post_id, sort_order);

create table if not exists public.post_likes (
  post_id uuid not null references public.posts (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now(),
  hidden boolean not null default false,
  constraint comment_length check (char_length(content) between 1 and 2000)
);

create index if not exists comments_post_idx on public.comments (post_id, created_at);

create table if not exists public.follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  following_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint no_self_follow check (follower_id <> following_id)
);

create index if not exists follows_following_idx on public.follows (following_id);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  target_type public.report_target not null,
  target_id uuid not null,
  reason text not null,
  created_at timestamptz not null default now(),
  unique (reporter_id, target_type, target_id),
  constraint report_reason_length check (char_length(reason) between 3 and 500)
);

create index if not exists reports_target_idx on public.reports (target_type, target_id, created_at desc);

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint no_self_block check (blocker_id <> blocked_id)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  type public.notification_type not null,
  payload jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists notifications_recipient_idx on public.notifications (recipient_id, created_at desc);

create or replace function public.is_blocked(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  );
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  desired text;
  candidate text;
  suffix int := 0;
begin
  desired := lower(coalesce(new.raw_user_meta_data ->> 'username', ''));
  if desired !~ '^[a-z0-9_]{3,20}$' then
    desired := 'driver' || substr(replace(new.id::text, '-', ''), 1, 8);
  end if;
  candidate := desired;
  while exists (select 1 from public.profiles where username = candidate) loop
    suffix := suffix + 1;
    candidate := substr(desired, 1, 14) || suffix::text;
    exit when suffix > 50;
  end loop;
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    candidate,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), 'Driver')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.protect_moderation_flags()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.role() is distinct from 'service_role' then
    if tg_table_name = 'posts' then
      new.hidden := old.hidden;
    elsif tg_table_name = 'comments' then
      new.hidden := old.hidden;
    elsif tg_table_name = 'vehicle_comments' then
      new.hidden := old.hidden;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists posts_protect_hidden on public.posts;
create trigger posts_protect_hidden
  before update on public.posts
  for each row execute function public.protect_moderation_flags();

drop trigger if exists comments_protect_hidden on public.comments;
create trigger comments_protect_hidden
  before update on public.comments
  for each row execute function public.protect_moderation_flags();

drop trigger if exists vehicle_comments_protect_hidden on public.vehicle_comments;
create trigger vehicle_comments_protect_hidden
  before update on public.vehicle_comments
  for each row execute function public.protect_moderation_flags();

create or replace function public.validate_event()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.ends_at <= new.starts_at then
    raise exception 'End time must be after the start time';
  end if;
  if tg_op = 'INSERT' and new.starts_at < now() - interval '5 minutes' then
    raise exception 'Start time must be in the future';
  end if;
  if auth.role() is distinct from 'service_role' and new.host_id is distinct from auth.uid() then
    raise exception 'You can only manage your own meets';
  end if;
  if tg_op = 'UPDATE' and old.host_id is distinct from new.host_id then
    raise exception 'The host cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists events_validate on public.events;
create trigger events_validate
  before insert or update on public.events
  for each row execute function public.validate_event();

create or replace function public.notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  host uuid;
  owner uuid;
  recipient uuid;
  actor_name text;
begin
  if tg_table_name = 'follows' then
    if new.follower_id = new.following_id then
      return new;
    end if;
    select display_name into actor_name from public.profiles where id = new.follower_id;
    insert into public.notifications (recipient_id, type, payload)
    values (
      new.following_id,
      'follow',
      jsonb_build_object('actor_id', new.follower_id, 'actor_name', actor_name)
    );
  elsif tg_table_name = 'post_likes' then
    select author_id into owner from public.posts where id = new.post_id;
    if owner is not null and owner <> new.user_id then
      select display_name into actor_name from public.profiles where id = new.user_id;
      insert into public.notifications (recipient_id, type, payload)
      values (
        owner,
        'like',
        jsonb_build_object('actor_id', new.user_id, 'actor_name', actor_name, 'post_id', new.post_id)
      );
    end if;
  elsif tg_table_name = 'comments' then
    select author_id into owner from public.posts where id = new.post_id;
    if owner is not null and owner <> new.author_id then
      select display_name into actor_name from public.profiles where id = new.author_id;
      insert into public.notifications (recipient_id, type, payload)
      values (
        owner,
        'comment',
        jsonb_build_object('actor_id', new.author_id, 'actor_name', actor_name, 'post_id', new.post_id, 'comment_id', new.id)
      );
    end if;
  elsif tg_table_name = 'vehicle_comments' then
    select owner_id into owner from public.vehicles where id = new.vehicle_id;
    if owner is not null and owner <> new.author_id then
      select display_name into actor_name from public.profiles where id = new.author_id;
      insert into public.notifications (recipient_id, type, payload)
      values (
        owner,
        'vehicle_comment',
        jsonb_build_object('actor_id', new.author_id, 'actor_name', actor_name, 'vehicle_id', new.vehicle_id, 'comment_id', new.id)
      );
    end if;
  elsif tg_table_name = 'event_attendees' then
    select host_id into host from public.events where id = new.event_id;
    if host is not null and host <> new.user_id then
      select display_name into actor_name from public.profiles where id = new.user_id;
      insert into public.notifications (recipient_id, type, payload)
      values (
        host,
        'event_join',
        jsonb_build_object('actor_id', new.user_id, 'actor_name', actor_name, 'event_id', new.event_id)
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists follows_notify on public.follows;
create trigger follows_notify after insert on public.follows
  for each row execute function public.notify();

drop trigger if exists likes_notify on public.post_likes;
create trigger likes_notify after insert on public.post_likes
  for each row execute function public.notify();

drop trigger if exists comments_notify on public.comments;
create trigger comments_notify after insert on public.comments
  for each row execute function public.notify();

drop trigger if exists vehicle_comments_notify on public.vehicle_comments;
create trigger vehicle_comments_notify after insert on public.vehicle_comments
  for each row execute function public.notify();

drop trigger if exists attendees_notify on public.event_attendees;
create trigger attendees_notify after insert on public.event_attendees
  for each row execute function public.notify();

create or replace function public.join_event(target uuid, car uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  ev public.events%rowtype;
  attending int;
begin
  if auth.uid() is null then
    raise exception 'Sign in to continue';
  end if;
  select * into ev from public.events where id = target;
  if not found or public.is_blocked(auth.uid(), ev.host_id) then
    raise exception 'Meet not found';
  end if;
  if ev.status <> 'scheduled' then
    raise exception 'This meet is no longer open';
  end if;
  if ev.ends_at < now() then
    raise exception 'This meet has ended';
  end if;
  if car is not null and not exists (
    select 1 from public.vehicles where id = car and owner_id = auth.uid()
  ) then
    raise exception 'That car is not in your garage';
  end if;
  select count(*) into attending from public.event_attendees where event_id = target;
  if ev.capacity is not null
     and attending >= ev.capacity
     and not exists (
       select 1 from public.event_attendees where event_id = target and user_id = auth.uid()
     ) then
    raise exception 'This meet is full';
  end if;
  insert into public.event_attendees (event_id, user_id, vehicle_id)
  values (target, auth.uid(), car)
  on conflict (event_id, user_id) do update set vehicle_id = excluded.vehicle_id;
end;
$$;

create or replace function public.event_detail(target uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  ev public.events%rowtype;
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in to continue';
  end if;
  select * into ev from public.events where id = target;
  if not found or public.is_blocked(auth.uid(), ev.host_id) then
    raise exception 'Meet not found';
  end if;
  if ev.visibility = 'private'
     and ev.host_id <> auth.uid()
     and not exists (
       select 1 from public.event_attendees where event_id = ev.id and user_id = auth.uid()
     )
     and ev.status <> 'scheduled' then
    raise exception 'Meet not found';
  end if;
  if ev.visibility = 'public' and ev.status <> 'scheduled' and ev.host_id <> auth.uid() and not exists (
    select 1 from public.event_attendees where event_id = ev.id and user_id = auth.uid()
  ) then
    raise exception 'Meet not found';
  end if;

  select jsonb_build_object(
    'event', to_jsonb(ev),
    'host', (
      select jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'display_name', p.display_name,
        'avatar_url', p.avatar_url,
        'cover_url', p.cover_url,
        'bio', p.bio,
        'home_city', case when p.show_city or p.id = auth.uid() then p.home_city else null end,
        'show_garage', p.show_garage,
        'show_city', p.show_city,
        'created_at', p.created_at
      )
      from public.profiles p where p.id = ev.host_id
    ),
    'attendee_count', (select count(*) from public.event_attendees a where a.event_id = ev.id),
    'joined', exists (select 1 from public.event_attendees a where a.event_id = ev.id and a.user_id = auth.uid()),
    'my_vehicle_id', (
      select a.vehicle_id from public.event_attendees a
      where a.event_id = ev.id and a.user_id = auth.uid()
    ),
    'attendees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', a.user_id,
        'joined_at', a.joined_at,
        'profile', jsonb_build_object(
          'id', p.id,
          'username', p.username,
          'display_name', p.display_name,
          'avatar_url', p.avatar_url,
          'cover_url', p.cover_url,
          'bio', p.bio,
          'home_city', case when p.show_city or p.id = auth.uid() then p.home_city else null end,
          'show_garage', p.show_garage,
          'show_city', p.show_city,
          'created_at', p.created_at
        ),
        'vehicle', case when v.id is null then null else jsonb_build_object(
          'id', v.id,
          'owner_id', v.owner_id,
          'make', v.make,
          'model', v.model,
          'year', v.year,
          'trim', v.trim,
          'color', v.color,
          'body_style', v.body_style,
          'transmission', v.transmission,
          'engine', v.engine,
          'power', v.power,
          'nickname', v.nickname,
          'description', v.description,
          'created_at', v.created_at
        ) end
      ) order by a.joined_at)
      from public.event_attendees a
      join public.profiles p on p.id = a.user_id
      left join public.vehicles v on v.id = a.vehicle_id
      where a.event_id = ev.id
        and not public.is_blocked(auth.uid(), a.user_id)
    ), '[]'::jsonb)
  ) into result;

  return result;
end;
$$;

create or replace function public.mark_notifications_read()
returns void
language sql
security definer
set search_path = public
as $$
  update public.notifications
  set read_at = now()
  where recipient_id = auth.uid()
    and read_at is null;
$$;

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to continue';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.is_blocked(uuid, uuid) from public;
revoke all on function public.join_event(uuid, uuid) from public;
revoke all on function public.event_detail(uuid) from public;
revoke all on function public.mark_notifications_read() from public;
revoke all on function public.delete_own_account() from public;
grant execute on function public.is_blocked(uuid, uuid) to authenticated;
grant execute on function public.join_event(uuid, uuid) to authenticated;
grant execute on function public.event_detail(uuid) to authenticated;
grant execute on function public.mark_notifications_read() to authenticated;
grant execute on function public.delete_own_account() to authenticated;

create or replace view public.event_cards
with (security_invoker = true) as
select
  e.*,
  p.username as host_username,
  p.display_name as host_display_name,
  (select count(*)::int from public.event_attendees a where a.event_id = e.id) as attendee_count
from public.events e
join public.profiles p on p.id = e.host_id;

create or replace view public.post_cards
with (security_invoker = true) as
select
  p.*,
  (select count(*)::int from public.post_likes l where l.post_id = p.id) as like_count,
  (select count(*)::int from public.comments c where c.post_id = p.id and not c.hidden) as comment_count
from public.posts p;

alter table public.profiles enable row level security;
alter table public.vehicles enable row level security;
alter table public.vehicle_photos enable row level security;
alter table public.vehicle_modifications enable row level security;
alter table public.vehicle_likes enable row level security;
alter table public.vehicle_comments enable row level security;
alter table public.events enable row level security;
alter table public.event_attendees enable row level security;
alter table public.posts enable row level security;
alter table public.post_images enable row level security;
alter table public.post_likes enable row level security;
alter table public.comments enable row level security;
alter table public.follows enable row level security;
alter table public.reports enable row level security;
alter table public.blocks enable row level security;
alter table public.notifications enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
for select to authenticated
using (
  id = auth.uid()
  or not public.is_blocked(auth.uid(), id)
  or exists (
    select 1 from public.blocks b
    where b.blocker_id = auth.uid() and b.blocked_id = profiles.id
  )
);

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

drop policy if exists vehicles_select on public.vehicles;
create policy vehicles_select on public.vehicles
for select to authenticated
using (
  not public.is_blocked(auth.uid(), owner_id)
  and (
    owner_id = auth.uid()
    or exists (
      select 1 from public.profiles p
      where p.id = vehicles.owner_id and p.show_garage
    )
  )
);

drop policy if exists vehicles_insert on public.vehicles;
create policy vehicles_insert on public.vehicles
for insert to authenticated
with check (owner_id = auth.uid());

drop policy if exists vehicles_update on public.vehicles;
create policy vehicles_update on public.vehicles
for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists vehicles_delete on public.vehicles;
create policy vehicles_delete on public.vehicles
for delete to authenticated
using (owner_id = auth.uid());

drop policy if exists vehicle_photos_all on public.vehicle_photos;
create policy vehicle_photos_select on public.vehicle_photos
for select to authenticated
using (exists (select 1 from public.vehicles v where v.id = vehicle_id));

drop policy if exists vehicle_photos_write on public.vehicle_photos;
create policy vehicle_photos_write on public.vehicle_photos
for all to authenticated
using (exists (select 1 from public.vehicles v where v.id = vehicle_id and v.owner_id = auth.uid()))
with check (exists (select 1 from public.vehicles v where v.id = vehicle_id and v.owner_id = auth.uid()));

drop policy if exists vehicle_mods_select on public.vehicle_modifications;
create policy vehicle_mods_select on public.vehicle_modifications
for select to authenticated
using (exists (select 1 from public.vehicles v where v.id = vehicle_id));

drop policy if exists vehicle_mods_write on public.vehicle_modifications;
create policy vehicle_mods_write on public.vehicle_modifications
for all to authenticated
using (exists (select 1 from public.vehicles v where v.id = vehicle_id and v.owner_id = auth.uid()))
with check (exists (select 1 from public.vehicles v where v.id = vehicle_id and v.owner_id = auth.uid()));

drop policy if exists vehicle_likes_select on public.vehicle_likes;
create policy vehicle_likes_select on public.vehicle_likes
for select to authenticated
using (true);

drop policy if exists vehicle_likes_write on public.vehicle_likes;
create policy vehicle_likes_write on public.vehicle_likes
for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists vehicle_comments_select on public.vehicle_comments;
create policy vehicle_comments_select on public.vehicle_comments
for select to authenticated
using (
  (not hidden or author_id = auth.uid())
  and not public.is_blocked(auth.uid(), author_id)
);

drop policy if exists vehicle_comments_insert on public.vehicle_comments;
create policy vehicle_comments_insert on public.vehicle_comments
for insert to authenticated
with check (author_id = auth.uid() and not hidden);

drop policy if exists vehicle_comments_update on public.vehicle_comments;
create policy vehicle_comments_update on public.vehicle_comments
for update to authenticated
using (author_id = auth.uid())
with check (author_id = auth.uid());

drop policy if exists vehicle_comments_delete on public.vehicle_comments;
create policy vehicle_comments_delete on public.vehicle_comments
for delete to authenticated
using (author_id = auth.uid());

drop policy if exists events_select on public.events;
create policy events_select on public.events
for select to authenticated
using (
  not public.is_blocked(auth.uid(), host_id)
  and (
    host_id = auth.uid()
    or exists (
      select 1 from public.event_attendees ea
      where ea.event_id = events.id and ea.user_id = auth.uid()
    )
    or (visibility = 'public' and status = 'scheduled')
  )
);

drop policy if exists events_insert on public.events;
create policy events_insert on public.events
for insert to authenticated
with check (host_id = auth.uid());

drop policy if exists events_update on public.events;
create policy events_update on public.events
for update to authenticated
using (host_id = auth.uid())
with check (host_id = auth.uid());

drop policy if exists events_delete on public.events;
create policy events_delete on public.events
for delete to authenticated
using (host_id = auth.uid());

drop policy if exists attendees_select on public.event_attendees;
create policy attendees_select on public.event_attendees
for select to authenticated
using (
  exists (select 1 from public.events e where e.id = event_attendees.event_id)
);

drop policy if exists attendees_delete on public.event_attendees;
create policy attendees_delete on public.event_attendees
for delete to authenticated
using (user_id = auth.uid());

drop policy if exists posts_select on public.posts;
create policy posts_select on public.posts
for select to authenticated
using (
  (not hidden or author_id = auth.uid())
  and not public.is_blocked(auth.uid(), author_id)
);

drop policy if exists posts_insert on public.posts;
create policy posts_insert on public.posts
for insert to authenticated
with check (
  author_id = auth.uid()
  and not hidden
  and (
    vehicle_id is null
    or exists (select 1 from public.vehicles v where v.id = vehicle_id and v.owner_id = auth.uid())
  )
);

drop policy if exists posts_update on public.posts;
create policy posts_update on public.posts
for update to authenticated
using (author_id = auth.uid())
with check (author_id = auth.uid());

drop policy if exists posts_delete on public.posts;
create policy posts_delete on public.posts
for delete to authenticated
using (author_id = auth.uid());

drop policy if exists post_images_select on public.post_images;
create policy post_images_select on public.post_images
for select to authenticated
using (exists (select 1 from public.posts p where p.id = post_id));

drop policy if exists post_images_write on public.post_images;
create policy post_images_write on public.post_images
for all to authenticated
using (exists (select 1 from public.posts p where p.id = post_id and p.author_id = auth.uid()))
with check (exists (select 1 from public.posts p where p.id = post_id and p.author_id = auth.uid()));

drop policy if exists post_likes_select on public.post_likes;
create policy post_likes_select on public.post_likes
for select to authenticated
using (true);

drop policy if exists post_likes_write on public.post_likes;
create policy post_likes_write on public.post_likes
for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists comments_select on public.comments;
create policy comments_select on public.comments
for select to authenticated
using (
  (not hidden or author_id = auth.uid())
  and not public.is_blocked(auth.uid(), author_id)
);

drop policy if exists comments_insert on public.comments;
create policy comments_insert on public.comments
for insert to authenticated
with check (author_id = auth.uid() and not hidden);

drop policy if exists comments_update on public.comments;
create policy comments_update on public.comments
for update to authenticated
using (author_id = auth.uid())
with check (author_id = auth.uid());

drop policy if exists comments_delete on public.comments;
create policy comments_delete on public.comments
for delete to authenticated
using (author_id = auth.uid());

drop policy if exists follows_select on public.follows;
create policy follows_select on public.follows
for select to authenticated
using (true);

drop policy if exists follows_insert on public.follows;
create policy follows_insert on public.follows
for insert to authenticated
with check (
  follower_id = auth.uid()
  and not public.is_blocked(auth.uid(), following_id)
);

drop policy if exists follows_delete on public.follows;
create policy follows_delete on public.follows
for delete to authenticated
using (follower_id = auth.uid());

drop policy if exists reports_insert on public.reports;
create policy reports_insert on public.reports
for insert to authenticated
with check (reporter_id = auth.uid());

drop policy if exists reports_select on public.reports;
create policy reports_select on public.reports
for select to authenticated
using (reporter_id = auth.uid());

drop policy if exists blocks_select on public.blocks;
create policy blocks_select on public.blocks
for select to authenticated
using (blocker_id = auth.uid());

drop policy if exists blocks_insert on public.blocks;
create policy blocks_insert on public.blocks
for insert to authenticated
with check (blocker_id = auth.uid());

drop policy if exists blocks_delete on public.blocks;
create policy blocks_delete on public.blocks
for delete to authenticated
using (blocker_id = auth.uid());

drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications
for select to authenticated
using (recipient_id = auth.uid());

revoke all on all tables in schema public from anon;
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on public.event_cards to authenticated;
grant select on public.post_cards to authenticated;

insert into storage.buckets (id, name, public)
values
  ('avatars', 'avatars', true),
  ('covers', 'covers', true),
  ('vehicle-photos', 'vehicle-photos', true),
  ('event-covers', 'event-covers', true),
  ('post-images', 'post-images', true)
on conflict (id) do nothing;

drop policy if exists nightshift_public_read on storage.objects;
create policy nightshift_public_read on storage.objects
for select to public
using (bucket_id in ('avatars', 'covers', 'vehicle-photos', 'event-covers', 'post-images'));

drop policy if exists nightshift_owner_insert on storage.objects;
create policy nightshift_owner_insert on storage.objects
for insert to authenticated
with check (
  bucket_id in ('avatars', 'covers', 'vehicle-photos', 'event-covers', 'post-images')
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists nightshift_owner_update on storage.objects;
create policy nightshift_owner_update on storage.objects
for update to authenticated
using (
  bucket_id in ('avatars', 'covers', 'vehicle-photos', 'event-covers', 'post-images')
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id in ('avatars', 'covers', 'vehicle-photos', 'event-covers', 'post-images')
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists nightshift_owner_delete on storage.objects;
create policy nightshift_owner_delete on storage.objects
for delete to authenticated
using (
  bucket_id in ('avatars', 'covers', 'vehicle-photos', 'event-covers', 'post-images')
  and (storage.foldername(name))[1] = auth.uid()::text
);

do $$
begin
  alter publication supabase_realtime add table public.events;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.event_attendees;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;
