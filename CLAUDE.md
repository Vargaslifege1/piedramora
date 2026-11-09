# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Piedra Mora is the public website + admin panel for a restaurant (delivery, takeaway and in-store menu browsing) in San Fernando del Valle de Catamarca, Argentina. Two physical sucursales: `maestro-quiroga` (Centro) and `intendente-lascano` (Oeste). There is no build system — it is plain HTML/CSS/JS served as static files, backed by Supabase (Postgres + Auth + Storage).

Respond and comment code in Rioplatense Spanish, briefly — this matches the project's existing conventions and the `.cursor/rules/piedra-mora.mdc` rules.

## Hard rules (from `.cursor/rules/piedra-mora.mdc` and `AGENTS.md`)

- **Stack is locked**: vanilla HTML/CSS/JS + Supabase only. Do not introduce frameworks, bundlers, or build tooling. Do not change existing colors or fonts.
- **Start of a task**: read `PROGRESO_FASE1.md` and run `git status` / `git log -3 --oneline` for current context. **End of a task**: update `PROGRESO_FASE1.md` and commit with a clear message. One task at a time — finish with a summary of files touched and how to test, then stop.
- **Never run SQL against the real database and never use secret keys.** Only write new migration files under `supabase/migrations/` (numbered, idempotent, commented). Remind the user to back up before they apply a migration themselves.
- **Never modify already-applied migrations** (currently 001–017 are applied in production; 018 is the latest). New changes always go in a new numbered file.
- Escape all user/client-supplied data with `PM.escaparHtml(...)` (see `js/core/utils.js`) or `textContent`. Never dump into `innerHTML` unescaped.
- Pricing, coupons, prizes, and order-state logic must be resolved server-side via Supabase RPC + RLS — never trust browser-side calculations for anything money- or state-related.
- Run `node --check <file>.js` on any JS file you edit (no test framework/build step exists, so this is the syntax safety net).
- Work only inside this project directory. Never create loose files on the Desktop or elsewhere outside the repo; use `.tmp/` for scratch/test output and clean it up afterward. Don't move/modify assets, backups, or data files without confirming first.

## Commands

There is no package.json / npm pipeline. Common commands:

```bash
# Syntax-check a JS file (the only "build" check available)
node --check main.js
node --check admin.js
node --check js/core/utils.js

# Validate data/cartas.json structural rules (ids, oferta dates, etc.)
node tools/verificar-carta.mjs

# Check whether a given oferta is currently "vigente" against real dates
node tools/probar-oferta-vigente.mjs
```

There is no dev server script in-repo; serve the directory statically (e.g. any static file server) to test `index.html` / `admin.html` in a browser.

## Architecture

### Frontend (static, no bundler)

- `index.html` + `main.js` + `style.css` — the public site: menu browsing ("carta"), cart, checkout, and WhatsApp order handoff.
- `admin.html` + `admin.js` + `admin.css` — the admin panel: Supabase-authenticated menu/config editing, image uploads to the `carta-imagenes` storage bucket, and (per `PROGRESO_FASE1.md`) order management with sound alerts for new pedidos.
- `js/core/utils.js` — shared `window.PM` namespace: Argentina-timezone date helpers (`hoyArgentina`), HTML escaping (`escaparHtml`), safe image/external URL validation, and oferta-date parsing (`parseFechaOferta`, offset `-03:00`).
- `js/core/carta-ids.js` — id helpers for menu items.
- `data/*.json` — local/static data shadowing what's stored in Supabase:
  - `cartas.json`: full menu (categories, products, prices, variations, adicionales, ofertas, per-sucursal availability, `agotado` flags).
  - `config.json`: business info and payment methods (`descuentoPorcentaje` per payment method).
  - `sucursales.json`: branch metadata including lat/lng.
  - `nube.json`: admin-panel cloud config pointer.

### Backend (Supabase)

- `supabase/migrations/NNN_*.sql` — the only source of truth for schema/RPC changes, applied in order. Read the header comments of recent migrations (017, 018) before writing a new one — they document prerequisites and which RPCs are "current" (e.g. `pm_calcular_pedido` as of 017 is the active version; don't touch it from an unrelated migration).
- Key RPCs: `crear_pedido` (creates an order, accepts optional `p_cupon`), `pm_calcular_pedido` (server-side price calculation — the authoritative source, not the browser), `valida_cupon` (coupon validation for checkout).
- `cupones` / `cupon_usos` / `cupon_intentos` tables (018): RLS restricts cupones/usos to the owner; intentos has no client access at all.
- The frontend already sends `p_cupon` (Fase 3C, done — see `PROGRESO_FASE1.md`): `main.js` validates live via `valida_cupon` and passes the code to `crear_pedido`. Don't assume "cupón not wired into the frontend yet" — check `PROGRESO_FASE1.md`'s Fase 3C section for current state before changing checkout/coupon code.
- RLS and storage policies are set up in `001_seguridad_rls_storage.sql`; per-sucursal admin access added in `017_admin_por_sucursal.sql`.
- `supabase-setup.sql` at repo root is an older/initial setup script — the authoritative incremental history is in `supabase/migrations/`.

### Order/pricing flow (see `PROGRESO_FASE1.md` for the full as-of-Fase-1 analysis)

Historically pricing was computed entirely client-side in `main.js` (base price → oferta substitution → + variación + adicionales → subtotal → payment-method discount → total), with no shipping cost and no server validation. Fase 1+ migrations are moving this calculation to the server (`pm_calcular_pedido`, `crear_pedido`) so the client is no longer the source of truth for money or order state. When touching checkout/pricing code, check which parts have already been moved server-side (read the latest migration files and `PROGRESO_FASE1.md`) rather than assuming `main.js` is authoritative.

### Backups and debug dirs

`backup-*/` directories and `_debug-escritorio/` are point-in-time snapshots/scratch, not active code — don't edit them, and don't treat them as current reference.
