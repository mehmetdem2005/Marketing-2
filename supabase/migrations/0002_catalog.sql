-- ============================================================================
-- Köyden — 0002_catalog: Mağaza & Katalog (stores/categories/products/images)
-- TOGAF Phase C (Data) · ISO 27002 · ADR-013 (katalog dikey dilimi)
-- Gizlilik zonu: Paylaşılan (public read) — satıcı kendi mağaza/ürününü yönetir.
-- Fiyat: price_minor (kuruş, bigint) — kayan nokta YOK (para birimi bütünlüğü).
-- ============================================================================

create extension if not exists "pg_trgm" with schema extensions;  -- isim/arama (ILIKE) için trigram

-- ============================================================================
-- stores (mağaza) — satıcıya (profiles) bağlı; public alanlar paylaşılan
-- ============================================================================
create table if not exists public.stores (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  name        text not null,
  slug        text not null unique,
  description text,
  logo_url    text,
  city        text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint store_name_len check (char_length(name) between 2 and 80)
);
create index if not exists idx_stores_owner on public.stores (owner_id);

drop trigger if exists trg_stores_updated_at on public.stores;
create trigger trg_stores_updated_at
  before update on public.stores
  for each row execute function public.set_updated_at();

-- ============================================================================
-- categories (kategori ağacı — parent_id)
-- ============================================================================
create table if not exists public.categories (
  id          uuid primary key default gen_random_uuid(),
  parent_id   uuid references public.categories (id) on delete set null,
  name        text not null,
  slug        text not null unique,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);
create index if not exists idx_categories_parent on public.categories (parent_id);

-- ============================================================================
-- products (ürün)
-- ============================================================================
create table if not exists public.products (
  id           uuid primary key default gen_random_uuid(),
  store_id     uuid not null references public.stores (id) on delete cascade,
  category_id  uuid references public.categories (id) on delete set null,
  name         text not null,
  slug         text not null,
  description  text,
  price_minor  bigint not null default 0,           -- kuruş (TRY)
  currency     text not null default 'TRY',
  stock        int not null default 0,
  unit         text,                                -- 'kg' | 'adet' | 'litre' ...
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint product_name_len check (char_length(name) between 2 and 140),
  constraint product_price_nonneg check (price_minor >= 0),
  constraint product_stock_nonneg check (stock >= 0)
);
create index if not exists idx_products_store on public.products (store_id);
create index if not exists idx_products_category on public.products (category_id);
create index if not exists idx_products_active on public.products (is_active);
-- Keşif/arama: isim + açıklama trigram (ILIKE %...%) — Trendyol benzeri hızlı arama.
create index if not exists idx_products_name_trgm on public.products using gin (name extensions.gin_trgm_ops);
create index if not exists idx_products_desc_trgm on public.products using gin (description extensions.gin_trgm_ops);

drop trigger if exists trg_products_updated_at on public.products;
create trigger trg_products_updated_at
  before update on public.products
  for each row execute function public.set_updated_at();

-- ============================================================================
-- product_images (Storage referansı)
-- ============================================================================
create table if not exists public.product_images (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.products (id) on delete cascade,
  url         text not null,
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);
create index if not exists idx_product_images_product on public.product_images (product_id);

-- ============================================================================
-- RLS — deny-by-default. Paylaşılan zon: public read; satıcı kendi kaydını yazar.
-- ============================================================================
alter table public.stores         enable row level security;
alter table public.categories     enable row level security;
alter table public.products       enable row level security;
alter table public.product_images enable row level security;

-- helper: bir mağaza auth kullanıcısına mı ait?
create or replace function public.owns_store(p_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.stores s
    where s.id = p_store_id and s.owner_id = auth.uid()
  );
$$;

-- categories: herkese açık okuma; yazma yalnız service_role (seed/admin) — politika yok = reddedilir.
drop policy if exists "categories_select_all" on public.categories;
create policy "categories_select_all" on public.categories
  for select using (true);

-- stores: aktif mağazalar herkese açık; sahibi her zaman görür/yönetir.
drop policy if exists "stores_select_public" on public.stores;
create policy "stores_select_public" on public.stores
  for select using (is_active or owner_id = auth.uid());
drop policy if exists "stores_insert_own" on public.stores;
create policy "stores_insert_own" on public.stores
  for insert with check (owner_id = auth.uid());
drop policy if exists "stores_update_own" on public.stores;
create policy "stores_update_own" on public.stores
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- products: aktif ürünler herkese açık; satıcı kendi mağazasının ürünlerini yönetir.
drop policy if exists "products_select_public" on public.products;
create policy "products_select_public" on public.products
  for select using (is_active or public.owns_store(store_id));
drop policy if exists "products_insert_own" on public.products;
create policy "products_insert_own" on public.products
  for insert with check (public.owns_store(store_id));
drop policy if exists "products_update_own" on public.products;
create policy "products_update_own" on public.products
  for update using (public.owns_store(store_id)) with check (public.owns_store(store_id));
drop policy if exists "products_delete_own" on public.products;
create policy "products_delete_own" on public.products
  for delete using (public.owns_store(store_id));

-- product_images: ürünle aynı görünürlük; yazma ürün sahibine.
drop policy if exists "product_images_select_public" on public.product_images;
create policy "product_images_select_public" on public.product_images
  for select using (
    exists (select 1 from public.products p
            where p.id = product_id and (p.is_active or public.owns_store(p.store_id)))
  );
drop policy if exists "product_images_write_own" on public.product_images;
create policy "product_images_write_own" on public.product_images
  for all using (
    exists (select 1 from public.products p where p.id = product_id and public.owns_store(p.store_id))
  ) with check (
    exists (select 1 from public.products p where p.id = product_id and public.owns_store(p.store_id))
  );

-- ============================================================================
-- Storage — ürün görselleri (public bucket; yazma kimliği doğrulanmışa)
-- ============================================================================
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do nothing;

drop policy if exists "product_images_read" on storage.objects;
create policy "product_images_read" on storage.objects
  for select using (bucket_id = 'product-images');
drop policy if exists "product_images_upload" on storage.objects;
create policy "product_images_upload" on storage.objects
  for insert with check (bucket_id = 'product-images' and auth.role() = 'authenticated');

-- ============================================================================
-- Seed — köy/doğal ürün kategorileri (Trendyol benzeri keşif için hazır içerik)
-- ============================================================================
insert into public.categories (name, slug, sort_order) values
  ('Bal & Arı Ürünleri',        'bal-ari-urunleri',      10),
  ('Zeytin & Zeytinyağı',       'zeytin-zeytinyagi',     20),
  ('Peynir & Süt Ürünleri',     'peynir-sut',            30),
  ('Kuruyemiş & Kurutulmuş',    'kuruyemis-kurutulmus',  40),
  ('Bakliyat & Tahıl',          'bakliyat-tahil',        50),
  ('Reçel & Salça',             'recel-salca',           60),
  ('Baharat & Bitki Çayı',      'baharat-bitki-cayi',    70),
  ('El Sanatları',              'el-sanatlari',          80)
on conflict (slug) do nothing;
