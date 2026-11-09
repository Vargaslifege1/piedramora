# PROGRESO — Piedra Mora (resumen)

Historial completo de todas las tareas y análisis: [docs/HISTORIAL.md](docs/HISTORIAL.md). Al terminar una tarea, agregar una línea en "Últimos cambios" (y pasar lo viejo al historial).

## Estado actual (2026-11-09)

- Rama `feature/fase-2-horarios` (74+ commits sobre `main`, sin conflictos); merge a `main` pendiente.
- Sitio: carta por sucursal, carrito, checkout con `crear_pedido`, cupones, fidelidad/premios, pedidos programados, estado Abierto/Cerrado, modalidades por día, mensaje de WhatsApp estilo Pedix.
- Admin: carta (con orden de categorías/productos), pedidos Kanban con sonido, agotados por sucursal, envíos por tramos, horarios y excepciones, cupones, fidelidad, estadísticas y CRM (dueño). Roles: dueño y encargado por sucursal.
- Seguridad: precios, descuentos, cupones, premios y estados se resuelven en el servidor (RPC + RLS); el navegador nunca decide dinero ni estados.

## Migraciones (`supabase/migrations/`)

Aplicadas en la base real: 000 a 025. **No aplicada: 026** (hasta que el dueño la audite y haga backup).

- 000 respaldo de la carta · 001 RLS y storage · 002 ids estables y `agotado` · 003 verificación de fase 0 (solo lectura)
- 010 tablas de pedidos, clientes, config y envío · 011 RLS/permisos/realtime de pedidos
- 012 limpieza de ofertas (hecha a mano) · 013 `crear_pedido` y `pm_calcular_pedido` · 014 ofertas en todas las categorías
- 015 envío por distancia (cuadras) · 016 estados de tablero y pagos · 017 admin por sucursal y agotados por sucursal
- 018 cupones · 019 fidelidad y premios · 020 registro de clientes y promos
- 021 seguridad de envío (coordenadas) y trigger de estados · 022 estadísticas y CRM (solo lectura)
- 023 teléfonos a 10 dígitos y fusión de clientes · 024 horarios en servidor y pedidos programados (`crear_pedido` de 16 parámetros)
- 025 modalidades por turno y excepciones por fecha · 026 `crm_clientes` busca por teléfono normalizado (SIN APLICAR)
- 099 rollback opcional de la carta (no se ejecuta salvo emergencia)

Vigentes: `crear_pedido` = 025 (16 parámetros); `pm_calcular_pedido` = 021; `sucursal_estado` = 025; `crm_clientes` = 022 (026 pendiente).

## Pendientes

- Dueño: auditar y aplicar 026 (backup antes) y probar la búsqueda "383 481" en Clientes.
- Dueño: revisar en pantalla horarios/excepciones (B), Cancelados (C), orden de la carta (E), cartel de modalidades en tarjetas y mensaje de WhatsApp (A).
- Opcional: cargar `alias`, `cbu` y `titular` en `data/config.json` (`pagos.transferencia`) para que salgan en el WhatsApp.
- H: estilos compactos (Cupones, Fidelidad y Envíos, Horarios en dos columnas), solo layout.
- Merge de `feature/fase-2-horarios` a `main` y despliegue del frontend con 026 aplicada si corresponde.
- Backups fuera del repo: `C:\Users\PC\Documents\backups-piedramora\` (antes-de-carta, carta-v1, carta-fase0); `backup-*/` está en `.gitignore`.

## Últimos cambios

- 2026-11-09: admin Horarios más claro y seguro (solo UX): título "Editando: <sucursal>", banner de modo forzado (ámbar/rojo) con "Volver a automático", turnos compactos con chips Retiro/Delivery, un único "Copiar <día> a todos los días" y barra sticky "Tenés cambios sin guardar" con aviso al cambiar de sucursal/pestaña/cerrar. Sin cambios de RPC, permisos ni reglas de guardado.
- 2026-11-09: admin Clientes más claro (solo presentación): una barra con buscador + chips de segmento + "Solo acepta promos", iniciales, badge con punto, ticket promedio y WhatsApp siempre visible (deshabilitado si no aceptó promos). Sin cambios de RPC ni SQL.
- 2026-11-09: limpieza (G): quitadas imágenes sin uso (`public/images/categorias/`, `assets/logo.png`, `assets/productos/PROMOS/2 cheese.jpg`) y backups del repo; PROGRESO reorganizado (historial en `docs/HISTORIAL.md`).
- 2026-11-09: cartel de modalidades en línea propia con ícono de moto en las tarjetas de sucursal (`main.js`, `style.css`).
- 2026-11-09: migración 026 (SIN APLICAR): búsqueda de clientes del CRM por teléfono normalizado.
- 2026-11-09: admin: orden de categorías y productos de la carta (dueño); tablero con Cancelados abierto sin scroll horizontal desde 1100 px.
- 2026-11-07: mensaje de WhatsApp estilo Pedix con emojis por campo (escapes `\u{...}`), verificado sin U+FFFD.
- 2026-11-09: admin: controles (time/date/select) con tema oscuro en todas las pestañas; Horarios con "Copiar a todos" por día en menú "⋯" y badge junto al nombre (solo UX).
