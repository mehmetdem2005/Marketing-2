# Köyden — Backend (Supabase)

Köyden pazaryeri için **Supabase** backend: Postgres (RLS), Auth (GoTrue), Storage,
Realtime ve Edge Functions. Bu repo `supabase/` CLI yapısını (migrations, seed, functions)
ve CI'yı içerir.

> Multi-repo: Android uygulaması ve **tüm mimari/karar/standart dokümanları** `marketing`
> reposundadır (`docs/`). Bu repo yalnız backend artefaktlarını barındırır.

## Yapı
```
supabase/
  config.toml          CLI yapılandırması
  migrations/          Şema + RLS (sürümlü SQL)
    0001_init.sql      Kimlik & profil tabanı + RLS (PII zonu)
  seed.sql             Yerel/demo veri
  functions/           Edge Functions (Faz 5)
```

## Güvenlik (özet — detay: marketing/docs/guvenlik.md)
- Her tabloda **RLS etkin + deny-by-default**.
- **Sır repoda yok.** `service-role` ve Stripe secret yalnız `supabase secrets set` ile env'de.
- Anon key tasarım gereği herkese açık; güvenlik RLS ile.

## Geliştirme
- `supabase start` (yerel stack; migration'ları uygular)
- `supabase db lint` (doğrulama)
- DB migration'ları canlıya **yalnız açık izinle** uygulanır.

## Fazlar
0 kimlik/profil tabanı (bu sürüm) → 3 stores/categories/products + Storage →
5 orders + RPC (`create_order`) + Stripe Edge (yönlendirme) → ...

---

**Standartlar:** TOGAF Phase C/D · ISO 27002 (erişim/minimizasyon) · 25012 (veri) · ADR-002/005/006/008.
