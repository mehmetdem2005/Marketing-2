-- ============================================================================
-- SeçAl — 0003_cart: Sepet (cart_items) · Faz 5a
-- TOGAF Phase C (Data) · ISO 27002 · ADR-016 (sepet dikey dilimi)
-- Gizlilik zonu: PII — sepet yalnız sahibine görünür/yazılır (RLS user_id = auth.uid()).
-- Sepet "başlığı" (carts) MVP'de cart_items'a (user_id anahtarlı) katlandı — gereksiz join yok.
-- ============================================================================

create table if not exists public.cart_items (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  product_id  uuid not null references public.products (id) on delete cascade,
  quantity    int  not null default 1,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint cart_qty_range check (quantity between 1 and 99),
  constraint cart_user_product_uniq unique (user_id, product_id)
);
create index if not exists idx_cart_items_user on public.cart_items (user_id);

drop trigger if exists trg_cart_items_updated_at on public.cart_items;
create trigger trg_cart_items_updated_at
  before update on public.cart_items
  for each row execute function public.set_updated_at();

-- ============================================================================
-- RLS — deny-by-default. PII: kullanıcı yalnız kendi sepetini görür/yönetir.
-- ============================================================================
alter table public.cart_items enable row level security;

drop policy if exists "cart_items_select_own" on public.cart_items;
create policy "cart_items_select_own" on public.cart_items
  for select using (user_id = auth.uid());
drop policy if exists "cart_items_insert_own" on public.cart_items;
create policy "cart_items_insert_own" on public.cart_items
  for insert with check (user_id = auth.uid());
drop policy if exists "cart_items_update_own" on public.cart_items;
create policy "cart_items_update_own" on public.cart_items
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "cart_items_delete_own" on public.cart_items;
create policy "cart_items_delete_own" on public.cart_items
  for delete using (user_id = auth.uid());

-- ============================================================================
-- RPC — atomik "sepete ekle" (varsa miktarı artır, yoksa ekle). RLS invoker.
-- ============================================================================
create or replace function public.add_to_cart(p_product_id uuid, p_qty int default 1)
returns void
language sql
set search_path = public
as $$
  insert into public.cart_items (user_id, product_id, quantity)
  values (auth.uid(), p_product_id, greatest(coalesce(p_qty, 1), 1))
  on conflict (user_id, product_id)
  do update set quantity   = least(public.cart_items.quantity + greatest(coalesce(p_qty, 1), 1), 99),
                updated_at = now();
$$;
