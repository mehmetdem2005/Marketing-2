-- ============================================================================
-- SeçAl — 0004_orders: Sipariş (orders/order_items + place_order RPC) · Faz 5b
-- TOGAF Phase C (Data) · ISO 27002 · ADR-018 (sipariş dikey dilimi)
-- Gizlilik zonu: PII — sipariş yalnız sahibine. order_items fiyat/ad SNAPSHOT'tur
-- (ürün sonradan değişse bile sipariş kaydı sabit kalır — veri tutarlılığı/ISO 25012).
-- ============================================================================

create table if not exists public.orders (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  total_minor  bigint not null default 0,
  status       text not null default 'pending',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint order_status_chk check (status in ('pending','confirmed','shipped','delivered','cancelled')),
  constraint order_total_nonneg check (total_minor >= 0)
);
create index if not exists idx_orders_user on public.orders (user_id);

drop trigger if exists trg_orders_updated_at on public.orders;
create trigger trg_orders_updated_at
  before update on public.orders
  for each row execute function public.set_updated_at();

create table if not exists public.order_items (
  id               uuid primary key default gen_random_uuid(),
  order_id         uuid not null references public.orders (id) on delete cascade,
  product_id       uuid references public.products (id) on delete set null,
  product_name     text not null,                 -- snapshot
  unit_price_minor bigint not null,               -- snapshot (kuruş)
  quantity         int not null,
  created_at       timestamptz not null default now(),
  constraint order_item_qty_pos check (quantity > 0)
);
create index if not exists idx_order_items_order on public.order_items (order_id);

-- ============================================================================
-- RLS — deny-by-default. PII: kullanıcı yalnız kendi siparişini görür.
-- ============================================================================
alter table public.orders      enable row level security;
alter table public.order_items enable row level security;

drop policy if exists "orders_select_own" on public.orders;
create policy "orders_select_own" on public.orders
  for select using (user_id = auth.uid());

drop policy if exists "order_items_select_own" on public.order_items;
create policy "order_items_select_own" on public.order_items
  for select using (
    exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid())
  );

-- ============================================================================
-- RPC place_order — sepetten atomik sipariş: toplam hesapla → order + order_items
-- (snapshot) → stok düş → sepeti temizle. security definer (stok güncellemesi RLS'i aşar).
-- ============================================================================
create or replace function public.place_order()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order uuid;
  v_total bigint;
  v_uid   uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Oturum yok'; end if;

  select coalesce(sum(p.price_minor * c.quantity), 0) into v_total
  from public.cart_items c join public.products p on p.id = c.product_id
  where c.user_id = v_uid;

  if v_total = 0 then raise exception 'Sepet boş'; end if;

  insert into public.orders (user_id, total_minor, status)
  values (v_uid, v_total, 'pending')
  returning id into v_order;

  insert into public.order_items (order_id, product_id, product_name, unit_price_minor, quantity)
  select v_order, p.id, p.name, p.price_minor, c.quantity
  from public.cart_items c join public.products p on p.id = c.product_id
  where c.user_id = v_uid;

  update public.products p
  set stock = greatest(p.stock - c.quantity, 0)
  from public.cart_items c
  where c.product_id = p.id and c.user_id = v_uid;

  delete from public.cart_items where user_id = v_uid;

  return v_order;
end;
$$;
