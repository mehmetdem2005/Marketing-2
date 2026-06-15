-- ============================================================================
-- SeçAl — 0005: Uyum & Ödeme altyapısı
-- TOGAF Phase B/C · ADR-019 (ödeme) + lisans-ve-uyum (gıda: 5996 işletme kayıt belgesi)
-- (1) stores.business_registration_no — satıcı GIDA İşletme Kayıt/Onay Belge No (esnaf zaten taşır).
-- (2) orders.payment_method — Faz A 'cod' (kapıda ödeme); Faz B 'online' (iyzico Pazaryeri).
-- ============================================================================

alter table public.stores
  add column if not exists business_registration_no text;

alter table public.orders
  add column if not exists payment_method text not null default 'cod';

alter table public.orders
  drop constraint if exists order_payment_method_chk;
alter table public.orders
  add constraint order_payment_method_chk check (payment_method in ('cod', 'online'));
