-- ============================================================================
-- Köyden — 0001_init: Kimlik & Profil tabanı + RLS (deny-by-default)
-- TOGAF Phase C (Data) · ISO 27002 (erişim/minimizasyon) · ADR-005, ADR-006
-- Gizlilik zonu: PII (profiles, addresses)
-- ============================================================================

-- --- Eklentiler ---
create extension if not exists "pgcrypto" with schema extensions;

-- --- Ortak: updated_at otomatik güncelleme ---
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- --- Roller ---
do $$
begin
  if not exists (select 1 from pg_type where typname = 'user_role') then
    create type public.user_role as enum ('buyer', 'seller', 'admin');
  end if;
end$$;

-- ============================================================================
-- profiles (PII) — auth.users 1:1
-- ============================================================================
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  role        public.user_role not null default 'buyer',
  full_name   text,
  phone       text,
  avatar_url  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint full_name_len check (full_name is null or char_length(full_name) <= 120)
);

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Yeni kullanıcı kaydında profil otomatik oluşturulur.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================================
-- addresses (PII)
-- ============================================================================
create table if not exists public.addresses (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  title        text not null,
  recipient    text not null,
  phone        text not null,
  line1        text not null,
  line2        text,
  district     text not null,
  city         text not null,
  postal_code  text,
  is_default   boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint title_len check (char_length(title) between 1 and 60)
);

create index if not exists idx_addresses_user on public.addresses (user_id);

drop trigger if exists trg_addresses_updated_at on public.addresses;
create trigger trg_addresses_updated_at
  before update on public.addresses
  for each row execute function public.set_updated_at();

-- ============================================================================
-- RLS — deny-by-default; politikalar açıkça izin verir
-- ============================================================================
alter table public.profiles  enable row level security;
alter table public.addresses enable row level security;

-- profiles: kullanıcı kendi profilini görür/günceller. (Public profil görünümü Faz 3.)
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- addresses: yalnız sahibi (CRUD).
drop policy if exists "addresses_select_own" on public.addresses;
create policy "addresses_select_own" on public.addresses
  for select using (auth.uid() = user_id);

drop policy if exists "addresses_insert_own" on public.addresses;
create policy "addresses_insert_own" on public.addresses
  for insert with check (auth.uid() = user_id);

drop policy if exists "addresses_update_own" on public.addresses;
create policy "addresses_update_own" on public.addresses
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "addresses_delete_own" on public.addresses;
create policy "addresses_delete_own" on public.addresses
  for delete using (auth.uid() = user_id);
