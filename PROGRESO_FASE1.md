# Fase 1 - Paso 1A: análisis del flujo actual de pedidos

Fecha: 2026-11-02  
Rama: `feature/fase-1-pedidos`  
Alcance: solo análisis. No se modificó código, no se ejecutó SQL y no se tocó la base.

## Archivos revisados

- `main.js`: carrito, precios, ofertas, checkout, dirección y envío a WhatsApp.
- `index.html`: formulario de checkout y campos de entrega/pago.
- `data/config.json`: negocio y medios de pago.
- `data/sucursales.json`: sucursales, coordenadas y botones.
- `data/cartas.json`: categorías, productos, precios, ofertas, variaciones y adicionales.
- `js/core/utils.js`: fecha de Argentina y control de agotado.
- `supabase/migrations/001_seguridad_rls_storage.sql` y `002_ids_estables_y_agotado.sql`: RLS y estructura actual de `public.carta`.

## (a) Fórmula exacta que usa hoy el cliente

La venta actual se calcula en el navegador. El servidor no participa.

1. **Precio base de una línea**
   - Si el producto tiene oferta válida, se usa el precio de oferta.
   - Si no, se usa `precios.delivery` en modalidad delivery/takeaway o `precios.mesa` en modalidad mesa.
   - Si falta la clave de la modalidad, se usa la otra (`main.js:1280-1288`).

2. **Cómo se decide una oferta** (`main.js:1290-1322`)
   - Se acepta si `tipoOferta` es `dia` o `semana`, o si `enOferta === true`.
   - Se toma `${clave}_oferta` (`delivery_oferta` o `mesa_oferta`).
   - Si esa clave falta, se usa la de la otra modalidad.
   - Si tampoco existe, se usa `preciosOferta[clave]` o el primer valor disponible de `preciosOferta`.
   - Solo se acepta si es numérico, mayor a 0 y menor al precio regular.
   - **No se valida el día de la semana ni una vigencia temporal.** `dia` y `semana` hoy son solo etiquetas visuales.

3. **Variación**
   - Se busca la opción por `id` dentro de las variaciones del producto.
   - Se suma `variacion.precio` al precio base (`main.js:1419-1437` y `1809-1811`).

4. **Adicionales**
   - Se busca cada adicional por `id` dentro del producto.
   - Se suma cada `adicional.precio` (`main.js:1439-1461` y `1811`).

5. **Precio unitario y subtotal de línea**
   - `precioUnitario = precioBase + variacion.precio + suma(adicionales.precio)`.
   - `subtotalLinea = precioUnitario * cantidad`.
   - No hay redondeo por línea porque todos los precios actuales son enteros.

6. **Subtotal del pedido**
   - `subtotal = suma(subtotalLinea)`.
   - Se calcula igual en la vista del checkout y en el mensaje de WhatsApp (`main.js:2191-2195`, `2794-2801`).

7. **Descuento por medio de pago** (`main.js:383-392`)
   - `descuento = Math.round(subtotal * porcentaje / 100)`.
   - `total = max(0, subtotal - descuento)`.
   - Hoy `efectivo` y `transferencia` tienen `0%` en `data/config.json`.

8. **Envío**
   - **No existe.** No hay precio de envío en `data/config.json` ni en el checkout.
   - El total mostrado y el total de WhatsApp son `subtotal - descuento`, sin envío.

## (b) Envío, ubicación y datos disponibles

- El checkout solo permite **Delivery** o **Retiro / Takeaway**.
- En Delivery se exige una dirección confirmada con texto, `lat` y `lng` (`main.js:2766-2776`).
- En Retiro no se pide dirección.
- La dirección se busca con Nominatim y se guarda como `{ texto, lat, lng }` (`main.js:2544-2570`). No se guarda distancia ni sucursal.
- La distancia usada para ordenar resultados es Haversine en línea recta (`main.js:846-861`), no distancia recorrida.
- Cada sucursal tiene coordenadas confiables en `data/sucursales.json`:
  - `maestro-quiroga`: `-28.4594712, -65.7846355`.
  - `intendente-lascano`: `-28.4677229, -65.8149113`.
- **No hay nombres ni datos de “La Estancita” en `data/sucursales.json`.** Las sucursales actuales son Maestro Quiroga y Oeste.
- Para cobrar envío falta definir:
  - base por sucursal;
  - cantidad de cuadras incluidas;
  - tramos y precios;
  - metros por cuadra;
  - redondeo de la distancia;
  - si el envío se cobra antes o después del descuento por pago.

Propuesta de configuración a validar:

```json
{
  "envio": {
    "base": 3000,
    "metrosPorCuadra": 100,
    "redondeo": "arriba",
    "sucursales": {
      "maestro-quiroga": {
        "tramos": [
          { "hastaCuadras": 10, "precio": 3000 },
          { "hastaCuadras": 20, "precio": 4000 }
        ]
      },
      "intendente-lascano": {
        "tramos": [
          { "hastaCuadras": 10, "precio": 6000 },
          { "hastaCuadras": 20, "precio": 7000 }
        ]
      }
    }
  }
}
```

## (c) Casos especiales y reglas que el servidor debe replicar

1. **Ofertas sin vigencia real**
   - `tipoOferta` no consulta el día. Si el servidor implementa horarios reales, cambia el comportamiento actual.
   - También existe el fallback entre modalidades: una oferta de delivery puede usarse en mesa y viceversa.

2. **Producto agotado** (`js/core/utils.js:49-53`)
   - Solo está agotado si `agotado === true`.
   - Y además `agotado_hasta_nuevo_aviso === true` o `agotado_fecha` es igual a la fecha de Argentina (`America/Argentina/Buenos_Aires`).
   - Hoy no hay productos agotados en `data/cartas.json`.

3. **Producto por sucursal**
   - Cada producto tiene `sucursales: []`. El servidor debe rechazar un producto que no pertenezca a la sucursal del pedido.

4. **Productos sin personalización**
   - Pizzas y promos no permiten variaciones ni adicionales (`main.js:118-124`).
   - Si se envían igual, el servidor debería rechazarlos.

5. **Lomos y milanesas**
   - Requieren elegir tipo de pan (`main.js:75`, `93-116`).
   - Las opciones se filtran por `pan|franc|arabe|árabe`; si no hay al menos 2, se usan opciones predeterminadas.
   - No permiten adicionales, aunque el producto los tenga en la carta (`main.js:1802-1803`).

6. **Variación obligatoria**
   - Si `variaciones.obligatorio === true`, no se puede confirmar sin variación.
   - El servidor debe exigirla y validar que el `id` exista en las opciones permitidas.

7. **Modalidad mesa**
   - `cartaPermitePedidos()` devuelve `false` cuando la modalidad es mesa (`main.js:1066-1072`).
   - Por eso el bloque de pedido para mesa del submit (`main.js:2760-2764`) es prácticamente inalcanzable.
   - Hoy mesa es solo consulta. Si se quieren pedidos de mesa, hay que cambiar esa regla y definir número de mesa.

8. **Cambios de precio mientras se completa el pedido**
   - Al abrir el checkout y al enviar se recalcula el carrito (`main.js:2093`, `2746`).
   - El servidor igual debe ser la fuente de verdad.

9. **Dirección en retiro**
   - Si el usuario elige retiro, puede quedar una dirección vieja en memoria, pero no se envía.

## (d) Recomendación de persistencia

### Mantener la carta actual

No conviene crear tablas de productos en esta fase:

- `public.carta` ya guarda la carta completa como JSONB en la fila `id = 1`.
- El admin ya escribe esa fila.
- Duplicar productos en tablas nuevas agregaría un riesgo de desincronización.
- La RPC puede leer `public.carta` y recalcular con la misma data que ve el cliente.

### Configuración de pedidos

Agregar una configuración singleton en Supabase, por ejemplo `public.config_pedidos` con JSONB:

- `pagos`: tipos habilitados y porcentajes de descuento.
- `envio`: base, tramos, sucursales y metros por cuadra.
- Coordenadas de sucursal usadas por el servidor.
- `moneda`, límites de texto y demás parámetros.

La configuración local `data/config.json` seguiría siendo el fallback visual del cliente.

### Tabla de pedidos

Recomendación: una tabla `public.pedidos` con los ítems como snapshot JSONB.

Campos mínimos sugeridos:

- `id uuid` primary key.
- `numero text unique not null` con formato `PM-0001`.
- `idempotency_key uuid unique` para evitar duplicados por doble clic o reintento.
- `created_at timestamptz`.
- `sucursal_id text`.
- `modalidad text` (`delivery_takeaway`).
- `tipo_entrega text` (`delivery` o `retiro`).
- `cliente_nombre`, `cliente_telefono`.
- `direccion_texto`, `direccion_lat`, `direccion_lng`.
- `distancia_km numeric`.
- `pago_tipo`, `pago_porcentaje`.
- `subtotal`, `descuento`, `envio`, `total` (numéricos).
- `envio_detalle jsonb` para auditoría del tramo aplicado.
- `items jsonb` con snapshot de cada línea.
- `notas`.
- `estado text` (`nuevo`, `preparando`, `en_camino`, `entregado`, `cancelado`).

Cada ítem del snapshot debería incluir:

```json
{
  "producto_id": "burger_cheeseburger",
  "nombre": "CHEESEBURGER",
  "variacion_id": "burger_cheeseburger_doble",
  "variacion_nombre": "DOBLE",
  "adicionales": [{ "id": "burger_cheeseburger_extra_queso", "nombre": "Queso Cheddar Extra", "precio": 1500 }],
  "precio_regular": 13000,
  "precio_oferta": 8700,
  "precio_unitario": 10200,
  "cantidad": 2,
  "subtotal": 20400
}
```

Ventaja: el pedido histórico no cambia si mañana se modifica la carta. Para reportes por producto se puede agregar después una tabla hija, pero no es necesaria para la bandeja inicial.

### Numeración

- Usar una secuencia de Postgres y formatear `PM-` + `lpad(..., 4, '0')`.
- No usar `count(*) + 1`: produce números repetidos con pedidos simultáneos.
- Con secuencia pueden quedar huecos si falla una inserción. Si se exige numeración consecutiva estricta, usar una fila contador con bloqueo (`for update`).

### RPC `crear_pedido`

Debe ser `security definer`, con `search_path` fijo, y recibir solo datos de entrada:

- `sucursal_id`, `modalidad`, `tipo_entrega`;
- nombre, teléfono, notas;
- dirección y coordenadas si es delivery;
- `pago_tipo`;
- ítems con `producto_id`, `variacion_id`, `adicionales_ids` y `cantidad`;
- `idempotency_key`.

La RPC debe:

1. Leer la carta y la configuración.
2. Validar sucursal, producto, disponibilidad, variación, adicionales y cantidades.
3. Recalcular precios, descuento y envío. **Nunca confiar en precios o totales enviados por el cliente.**
4. Insertar el pedido.
5. Devolver número, ítems calculados y totales.
6. Si la `idempotency_key` ya existe, devolver el pedido existente sin duplicarlo.

### RLS y seguridad

- Activar RLS en `public.pedidos`.
- No dar `select` ni `insert` directo a `anon`.
- Permitir `execute` de la RPC a `anon` (es el checkout público).
- Permitir `select` y `update` solo a administradores autenticados mediante `public.es_admin()`.
- No guardar claves secretas en el repositorio.
- Limitar largos de textos y cantidades en la RPC.
- Escapar los datos del pedido al renderizarlos en la bandeja admin para evitar XSS.
- Evaluar rate limiting o captcha para evitar spam de pedidos falsos.

## (e) Riesgos y bugs detectados

1. **La venta actual no se guarda en ningún lado.** El submit solo abre WhatsApp (`main.js:2810-2818`).
2. **No se vacía el carrito después de enviar.** Un segundo clic genera otro mensaje y, con la nueva lógica, otro pedido.
3. **No hay idempotencia.** Hace falta una clave única por intento de checkout.
4. **`window.open` después de una espera puede quedar bloqueado** en navegadores móviles. Si se guarda primero en Supabase, hay que resolver el gesto del usuario.
5. **El número de pedido no puede aparecer en el mensaje de WhatsApp** si se abre WhatsApp antes de que responda la RPC.
6. **El servidor puede calcular un total distinto al mostrado** si la carta cambió o si el cliente tenía datos locales viejos. Hay que definir si se acepta, se avisa o se bloquea.
7. **Ofertas:** replicar el comportamiento actual implica ignorar día y semana; implementar vigencia real cambia precios actuales.
8. **La distancia es en línea recta.** Cobrar “cuadras” con Haversine puede diferir bastante de la distancia real de manejo.
9. **“La Estancita” no existe en las sucursales actuales.** Hay que confirmar si es otra sucursal, un alias o un nombre viejo.
10. **Si `public.carta` está vacía o sin la fila `id = 1`, la RPC no puede calcular.** Antes de activar pedidos hay que asegurar que la nube tenga la carta publicada.
11. **Los pedidos contienen datos personales.** La bandeja admin y las políticas RLS son obligatorias; no debe quedar lectura pública.
12. **El teléfono se guarda tal como se muestra.** Conviene guardar también los dígitos normalizados y validar 8 a 15 dígitos.
13. **Las notas no tienen límite en el HTML.** La RPC debe limitar el largo.
14. **Mesa hoy es solo lectura.** No hay número de mesa estructurado, solo texto libre en observaciones.
15. **El descuento se redondea con `Math.round`.** En Postgres conviene usar `numeric` y `round` para que no cambie el resultado por centavos.
16. **El envío no está contemplado en el mensaje de WhatsApp ni en el checkout.** Hay que agregar la línea y decidir si el descuento por pago aplica al envío.

## (f) Preguntas antes de implementar 1B

1. ¿El envío es un precio base más un adicional por cuadra, o son tramos cerrados? ¿La base incluye las primeras cuadras?
2. ¿Cuántos metros equivale una cuadra y cómo se redondea la distancia (arriba, abajo, al tramo más cercano)?
3. ¿“La Estancita” es una sucursal nueva, un alias de `intendente-lascano` o un nombre anterior? ¿Qué coordenadas y qué tarifa tiene?
4. ¿El descuento por medio de pago se aplica también al envío o solo a los productos?
5. ¿Mantenemos las ofertas como están (siempre activas, con etiqueta día/semana) o implementamos vigencia real? Si es real, ¿qué días aplica cada una?
6. ¿La numeración puede tener huecos por pedidos fallidos, o tiene que ser estrictamente consecutiva?
7. ¿El número `PM-0001` tiene que aparecer en el mensaje de WhatsApp, o alcanza con verlo en la bandeja admin?
8. Si Supabase falla, ¿abrimos WhatsApp igual automáticamente y guardamos el pedido después, o mostramos un aviso?
9. Si el total del servidor no coincide con el del cliente, ¿se informa y se pide confirmación, se usa el del servidor sin avisar, o se cancela?
10. ¿La configuración de envío y pagos se edita desde el admin en Supabase, o se deja fija en una migración por ahora?
11. ¿Los pedidos de mesa siguen siendo solo consulta? Si no, ¿cómo se identifica la mesa?
12. ¿Aprobás guardar los ítems como snapshot JSONB dentro de `pedidos`, o preferís tabla hija `pedido_items` desde el inicio?

## Paso 1C: RPC `crear_pedido` (histórico)

Las tablas `config_pedidos`, `pedidos`, la secuencia de numeración y las políticas RLS **ya están creadas** (migraciones 010 y 011, ejecutadas y verificadas).

`supabase/migrations/013_crear_pedido.sql` fue reemplazada por la versión definitiva que ya está en la base (parámetros `p_metodo_pago` y `p_zona_envio` incluidos):

- Crea `public.crear_pedido(...)` como `security definer` y `search_path = ''`.
- Recibe sucursal, modalidad, datos del cliente, dirección/GPS, pago, notas, ítems y `p_idempotency_key`.
- Vuelve a leer la carta y `config_negocio`; no confía en precios ni totales del cliente.
- Valida sucursal, producto, agotado, variaciones, adicionales, cantidades y categorías sin personalización (`pizza`, `promo`).
- Repite en SQL la lógica de lomos/milanesas solo con pan y las opciones de pan sintéticas.
- Replica precios regulares y de oferta, variaciones, adicionales y descuento por forma de pago.
- Guarda `items_snapshot` y devuelve número de pedido, ítems y totales calculados.
- Es idempotente por `idempotency_key`: si ya existe, devuelve el pedido existente sin duplicarlo.
- Permisos: ejecución solo para `anon` y `authenticated`; acceso directo a `pedidos` sigue cerrado.
- Decisión provisional de envío: `costo_envio = 0` y `zona_envio = 'Zona normal'` para delivery, porque el checkout actual no calcula envío. Queda pendiente definir zonas/tramos reales.

`main.js` quedó adaptado para el paso 1C:

- Genera una clave UUID por intento de checkout y la reutiliza si falla el guardado y el usuario reintenta.
- Guarda el pedido con `crear_pedido` antes de abrir WhatsApp.
- Abre una ventana en blanco de forma síncrona para no perder el gesto del usuario y luego la redirige a `wa.me`.
- Usa los ítems, totales y `numero_orden` del servidor en el mensaje cuando el guardado funciona.
- Si Supabase falla o no está configurado, continúa con el mensaje calculado en el cliente para no bloquear la venta.
- Si el guardado fue exitoso, vacía el carrito y cierra el checkout.
- Evita doble envío con un bloqueo mientras la RPC está en curso.

Pendientes antes de dar 1C por cerrado:

1. Ejecutar `013_crear_pedido.sql` en la base con confirmación explícita.
2. Probar un pedido real de delivery y uno de retiro.
3. Probar doble clic y reintento con la misma clave.
4. Probar el fallback cuando Supabase no responde.
5. Definir si el total del servidor se muestra/avisa cuando difiere del total local.
6. Definir zonas y costo de envío reales.

## Estado real al 2026-11-03

### Paso 1B: migraciones 010 y 011 ejecutadas

- Las migraciones `010_fase1_tablas_pedidos.sql` y `011_pedidos_rls_y_ajustes.sql` ya se ejecutaron en la base del usuario y fueron verificadas.
- Verificación de permisos con `anon`:
  - `public.pedidos` responde `401`.
  - `public.clientes` responde `401`.
  - `public.config_negocio` responde `200`.
  - `public.zonas_envio` responde `200`.

### Limpieza de ofertas: hecha a mano por el usuario

- Se quitaron manualmente todos los campos cuyo nombre contiene `oferta` (`delivery_oferta`, `mesa_oferta` y `tipoOferta`, con o sin mayúsculas) de los productos que **no** pertenecen a la categoría `promo`.
- Se aplicó tanto en `data/cartas.json` como en la nube (`public.carta`, fila `id = 1`).
- Solo quedaron con oferta:
  - `promo_combo_2_cheeseburger`
  - `promo_combo_pizza_lomo`
- Respaldos existentes:
  - Archivo local: `backup-carta-fase0/cartas-antes-de-ofertas.json`.
  - Nube: tabla `backups.carta_antes_ofertas`.
- Commit: `chore: ofertas solo en categoria promo`.
- **No volver a limpiar ofertas.**

### Migración 012

- `supabase/migrations/012_limpiar_ofertas.sql` queda solo como registro de la limpieza manual.
- Es idempotente y está marcada como "ya ejecutado a mano".
- **No ejecutarla** contra la base; no se ejecutó desde el proyecto.

### Paso 1B2: ofertas para cualquier producto (hecho)

- La oferta se detecta solo si el precio de oferta es un número válido (mayor a cero) y la vigencia está activa.
- Campos opcionales en cualquier producto:
  - `oferta_hasta`: texto ISO con offset `-03:00` (`America/Argentina/Buenos_Aires`).
  - `oferta_desde`: se conserva por compatibilidad, pero la interfaz ya no lo carga.
- Reglas:
  - `dia` y `semana`: oferta activa siempre, sin fecha.
  - `fecha`: oferta activa hasta `oferta_hasta`.
  - Fuera de fecha se muestra el precio regular y sin cartel.
- La comparación se hace por instante con el offset argentino, nunca con la hora local del dispositivo.
- `tipoOferta` tiene tres modos excluyentes: `dia`, `semana` y `fecha`. No afecta la detección de la oferta; define el cartel y, en `fecha`, exige `oferta_hasta`.
- Carteles:
  - `dia`: `⚡ OFERTA DEL DÍA`.
  - `semana`: `🔥 OFERTA DE LA SEMANA`.
  - `fecha`: `Hasta el DD/MM`, con estilo visual del día.
- Admin:
  - Las ofertas están disponibles para **todos los productos**, sin importar la categoría.
  - Un único selector "Tipo de oferta": Oferta del día / Oferta de la semana / Hasta una fecha.
  - Si se elige "Hasta una fecha", aparece un único campo de fecha (`type="date"`); se guarda a las 23:59 de Argentina.
  - Sin botones rápidos, horas intermedias ni "Limpiar fechas".
  - Las ofertas de día y semana no guardan fecha; solo "Hasta una fecha" guarda `oferta_hasta`.
  - Ya no se advierte ni se borra la oferta al cambiar de categoría.
- Verificación:
  - `tools/verificar-carta.mjs` valida IDs, precios, ofertas en cualquier producto, formato ISO y los tres modos de `tipoOferta`.
  - `tools/probar-oferta-vigente.mjs` prueba `ofertaVigente` con fechas `-03:00` en cuatro casos.

## Checkout con `crear_pedido` (2026-11-03)

- `crear_pedido` definitivo = migraciones **013** y **014**. La función que corre en la base usa `p_metodo_pago` y `p_zona_envio`.
- El checkout de `main.js` llama a `crear_pedido` con timeout de 10 segundos.
- Si Supabase falla, hay timeout, red caída o Supabase no está configurado, se envía igual por WhatsApp con el mensaje calculado en el navegador, sin número de pedido y con la primera línea "PEDIDO SIN REGISTRAR EN EL SISTEMA".
- Si el servidor rechaza el pedido, se pide confirmación antes de enviar por WhatsApp.
- Si el total del servidor difiere del total mostrado en pantalla, se avisa y se pide confirmación.
- Mesa es solo lectura: no se registra pedido ni se abre WhatsApp.

## Envío por distancia en cuadras (2026-11-03)

- El envío se cobra por **distancia en línea recta** desde la sucursal hasta la dirección del cliente, a **100 m por cuadra**. No se usa un selector de zonas.
- Tabla `tramos_envio`: 0 a 15 cuadras `$3000`, 16 a 24 `$4500`, 25 o más `$6000`.
- Función pública `cotizar_envio(p_sucursal_id text, p_lat numeric, p_lng numeric)` devuelve `{ costo_envio, cuadras, metros, por_distancia }`.
- `crear_pedido` calcula el mismo costo en el servidor cuando recibe `lat` y `lng`, con `p_zona_envio = null`.
- La zona fija "La Estancita" fue desactivada; ya no existe como zona.
- La tabla, los tramos y la función fueron aplicados a mano en Supabase (no desde una migración del proyecto).
- El checkout llama a `cotizar_envio` con timeout de 8 segundos, muestra la línea "Envío" con el costo y las cuadras, y recotiza al cambiar dirección, sucursal o tipo de entrega.
- El descuento por medio de pago se aplica solo a los productos, nunca al envío.
- El total mostrado es `subtotal - descuento + envío`; el mensaje de WhatsApp usa los montos del servidor y muestra las cuadras cuando están disponibles.
- La tabla `tramos_envio` y la función `cotizar_envio` quedaron registradas en `supabase/migrations/015_envio_por_distancia.sql` (ya aplicadas a mano en Supabase).

## Bandeja de pedidos en el admin (2026-11-03)

- Nueva navegación **Carta / Pedidos** en `admin.html`, con pestañas y badge de pendientes.
- La bandeja carga los últimos 100 pedidos, más nuevos primero.
- Filtros: estado (por defecto pendientes y confirmados), sucursal y fecha (hoy, últimos 7 días, todos).
- Cada pedido se abre en un detalle con ítems, variación, adicionales, notas, dirección con enlace a Google Maps y botón de WhatsApp.
- Acciones por estado: pendiente → Confirmar/Cancelar; confirmado → Entregado/Cancelar. Cancelar y Entregado piden confirmación y actualizan solo la columna `estado`.
- Realtime sobre INSERT y UPDATE de `pedidos`: los nuevos aparecen arriba, con aviso visual y sonido corto activado con un clic ("Activar sonido").
- Si Realtime falla, quedan el botón **Actualizar** y el refresco automático cada 60 segundos.
- Todos los datos escritos por el cliente se escapan con `PM.escaparHtml`; el teléfono de WhatsApp se arma solo con dígitos.
- Si la sesión vence o no hay permisos, se muestra un aviso claro sin romper el resto del admin.

## Aviso de privacidad en el checkout (2026-11-03)

- Se agregó el aviso de la Ley 25.326 al pie del formulario de checkout, justo arriba del botón de enviar.
- El texto es chico, legible y no bloquea el envío: no hay casilla obligatoria.
- La frase "escribiéndonos por WhatsApp" muestra el número de la sucursal elegida cuando está disponible.
- El número se actualiza al abrir el checkout y al cambiar de sucursal.
- Archivos: `index.html`, `style.css`, `main.js`.

## Pantalla "Pedido recibido" en el checkout (2026-11-03)

- Cuando `crear_pedido` responde bien, además de abrir WhatsApp se muestra un modal accesible con:
  - "¡Pedido recibido!" y el número (`PM-0001`).
  - Total y modalidad.
  - Aviso "Enviá el mensaje de WhatsApp que se abrió para que lo confirmemos".
  - "Tiempo estimado: X minutos" solo si `config_negocio.tiempo_estimado_entrega` tiene un valor mayor a cero. Hoy es `null`, así que no se muestra.
- El tiempo estimado se lee con el cliente público de Supabase desde `config_negocio`.
- Si el pedido no se pudo registrar (fallback), el modal cambia a "Pedido enviado por WhatsApp" y muestra "Tu pedido se envía por WhatsApp. Esperá nuestra confirmación.".
- El botón "Volver a la carta" cierra el modal y el checkout. Se ve bien en celular y en escritorio.
- Archivos: `index.html`, `style.css`, `main.js`.

## Sección "Envíos" en el admin (2026-11-03)

- Nueva pestaña **Envíos** en `admin.html`, junto a Carta y Pedidos.
- **Configuración general** (`config_negocio`, upsert por `clave`):
  - `metros_por_cuadra`: entero entre 50 y 300.
  - `tiempo_estimado_entrega`: entero de minutos; vacío se guarda sin valor y se lee como `null` (la columna `valor` es `jsonb not null`, así que no admite `NULL` de SQL).
  - `descuentos_pago`: objeto `{ efectivo, transferencia }`, ambos entre 0 y 100.
- **Costo base Zona normal** (`zonas_envio`): se edita el costo, si usa tramos y si está activa, por sucursal.
- **Tramos** (`tramos_envio`): listar, agregar, editar, activar/desactivar y borrar con confirmación.
- Validaciones de tramos: enteros >= 0, `hasta >= desde`, costo >= 0 y sin superposición entre tramos activos del mismo alcance (todos o sucursal).
- Si el último tramo activo no llega a 999 cuadras, se muestra un aviso para no dejar envíos sin precio.
- Referencia visible: "La distancia se mide en línea recta desde la sucursal. Una cuadra cuenta como X metros", con X leído de `config_negocio`.
- Los errores de carga, guardado y permisos se muestran como avisos claros. Toda lectura pública y escritura admin vía RLS existente.
- Archivos: `admin.html`, `admin.js`, `admin.css`.

Pendiente:
- Probar la sección Envíos en la nube y ajustar tramos reales si hace falta.
- Confirmar que no queden claves o variables sin usar en otros módulos.

## Descuentos por medio de pago desde `config_negocio` (2026-11-04)

- El checkout lee los descuentos desde `public.config_negocio`, clave `descuentos_pago`, con el cliente público de Supabase.
- Formato esperado del valor: `{"efectivo": n, "transferencia": n}` con porcentajes entre 0 y 100.
- Si la lectura falla, no hay Supabase configurado o la clave no existe, se mantienen los porcentajes de `data/config.json` como respaldo.
- La lectura se hace al cargar la configuración de la app y se reintenta al abrir el checkout y antes de enviar el pedido.
- La pantalla del checkout y el mensaje de WhatsApp usan los porcentajes leídos (el servidor sigue recalculando con `config_negocio` en `crear_pedido`).
- El descuento se aplica solo al subtotal de productos, nunca al envío.
- Texto actualizado en el checkout: `Descuentos vigentes (solo productos, no el envío): ...`.
- Archivos modificados: `main.js`, `PROGRESO_FASE1.md`.

Cómo probar:
1. En Supabase, `config_negocio` con `clave = descuentos_pago` y valor `{"efectivo": 10, "transferencia": 5}`.
2. Abrir la carta y el checkout: las opciones de pago deben mostrar `10% OFF` y `5% OFF`, y la nota debe listar ambos porcentajes.
3. Verificar que el total sea `subtotal - descuento + envío` y que el descuento no se aplique al envío.
4. Elegir cada medio de pago y confirmar que el mensaje de WhatsApp muestre el porcentaje y el descuento correctos.
5. Borrar o renombrar temporalmente la clave `descuentos_pago` y comprobar que se usan los valores de `data/config.json`.
6. Ejecutar `node --check main.js`.

## Ajustes de accesibilidad y validación de envíos (2026-11-04)

- Modal "Pedido recibido" (`main.js`):
  - `Escape` cierra solo el modal, sin cerrar la carta ni el checkout que quede detrás.
  - Se agregó focus trap: `Tab` y `Shift+Tab` quedan dentro del modal.
  - Al cerrarse, el foco vuelve al elemento que lo abrió; si ya no es visible (por ejemplo, el botón de envío del checkout cerrado), vuelve al panel de la carta.
- Pestaña Envíos (`admin.js`):
  - El aviso de "hueco al final" (último tramo activo menor a 999) ahora también aparece al cargar la pestaña, no solo al guardar o activar un tramo.
  - Al cargar se evalúa el conjunto efectivo de cada sucursal (tramos globales + los de esa sucursal) y se listan las sucursales con hueco.
  - La validación de superposición ahora usa ese mismo conjunto efectivo: un tramo global choca con cualquier tramo activo de cualquier sucursal, y un tramo de sucursal choca con los globales y con los de su propia sucursal. El mensaje indica el rango y la sucursal del tramo en conflicto.
  - Junto a "Tramos por cuadras" se muestra la referencia `1 cuadra = X metros`, leída de `config_negocio.metros_por_cuadra`.
- Archivos modificados: `main.js`, `admin.js`, `admin.html`, `PROGRESO_FASE1.md`.

Cómo probar:
1. Con la carta abierta, enviar un pedido y comprobar que `Escape` cierra el modal sin cerrar la carta; recorrer con `Tab` y verificar que el foco no sale del modal.
2. Al cerrar, verificar que el foco vuelve al botón que abrió el modal o al panel de la carta.
3. Entrar a la pestaña Envíos con un último tramo activo menor a 999 y confirmar que el aviso aparece sin guardar nada.
4. Crear un tramo global que se superponga con uno de una sucursal y verificar que el guardado se bloquea con el mensaje correspondiente.
5. Cambiar `metros_por_cuadra` y confirmar que la referencia junto a Tramos se actualiza.
6. Ejecutar `node --check main.js` y `node --check admin.js`.

## Centro de pedidos Kanban y aviso sonoro (2026-11-04)

### Aviso de pedido nuevo (`admin.js`, `admin.html`, `admin.css`)

- Se reemplazó el pitido por un "ding-dong" de dos notas generado con Web Audio API, sin archivos.
- El aviso se repite cada ~8 segundos mientras haya pedidos en `pendiente` con `sincronizado !== false`; se detiene al atenderlos o al silenciar.
- El audio se desbloquea con el primer clic en el admin. Si sigue bloqueado se muestra "Activá el sonido con un clic".
- Botón de silencio/activación y control de volumen, con preferencias persistidas en `localStorage` (`piedraMoraAdminSonido` y `piedraMoraAdminVolumen`). Por defecto: sonido activo y volumen 70%.
- El título de la pestaña parpadea con `(N) Nuevo pedido` y el badge de la pestaña Pedidos muestra el mismo conteo, excluyendo pedidos no sincronizados.

### Tablero de pedidos (`admin.html`, `admin.js`, `admin.css`)

- La pestaña Pedidos ahora es un tablero Kanban con columnas: Nuevos, En preparación, Listos para entregar, En camino (solo delivery), Completados y Cancelados.
- Cancelados arranca colapsada en escritorio y se puede expandir/colapsar.
- Barra superior: período por día o rango, navegación Ayer/Hoy/Siguiente, filtro por sucursal, vista tablero/lista, exportación CSV y filtros rápidos Todos / Para llevar / Delivery.
- En este negocio no se ofrecen pedidos para mesa: se quitó "En el local" de las pestañas y de los textos del tablero. Los retiros pasan de Listos directo a Completados, sin En camino.
- Tarjeta: número PM-XXXX, hora, cliente, modalidad con ícono, sucursal, medio de pago, estado de pago, total, ítems expandibles, botón principal de avance, imprimir ticket, "Marcar pagado" y cancelar con confirmación.
- "Marcar pagado" aparece si `pagado = false` y el medio no es efectivo; con efectivo, recién desde Listos, En camino o Completados.
- Impresión con `window.print()` y estilos `@media print` para un ticket simple de 80 mm.
- Los pedidos con `sincronizado = false` no se muestran ni se cuentan como ventas.
- Realtime: los INSERT y UPDATE actualizan o mueven solo la tarjeta afectada y los contadores de columna, sin reemplazar todo el tablero ni perder el scroll. El re-render completo queda para cambios de filtros, período o vista.
- Se cargan hasta 500 pedidos recientes para poder navegar fechas.

### Modelo de datos y migración 016

Archivo nuevo: `supabase/migrations/016_pedidos_estados_pagos.sql`. **No fue ejecutado.**

- Mantiene `confirmado` en la base y lo muestra como "En preparación" (sin reescribir datos).
- Agrega `listo` y `en_camino` al check de estados.
- Agrega `pagado boolean not null default false` y `pagado_en timestamptz`.
- El check de modalidad no se modifica.
- Amplía el `grant update` a `estado, pagado, pagado_en` y mantiene la política RLS con `public.es_admin()`.
- El trigger `public.pm_pedidos_actualizar_clientes()` no se recrea ni se modifica: sigue sumando o restando fidelidad solo al entrar o salir de `entregado`.

`admin.js` tolera la migración pendiente: si las columnas de pago no existen, carga los pedidos sin ellas y oculta la acción de pago hasta aplicar la migración.

**Antes de aplicar la migración 016, hacer backup de la base.**

### Cómo probar

1. Primer clic en el admin: el aviso debe pasar de "Activá el sonido con un clic" a "Sonido activo".
2. Crear o simular un pedido nuevo y verificar el ding-dong, la repetición cada ~8 s, el título parpadeante y el badge.
3. Atender el pedido (avanzar estado) y confirmar que el sonido y el parpadeo se detienen.
4. Probar silencio y volumen; recargar y verificar que se recuerdan.
5. Verificar las columnas y que un pedido de retiro pase de Listos a Completados.
6. Probar filtros de período, fecha, sucursal, modalidad y exportación CSV.
7. Probar imprimir un ticket, marcar pagado y cancelar con confirmación.
8. Con dos sesiones, cambiar un estado y verificar que la tarjeta se mueva sin recargar el tablero ni perder scroll.
9. Ejecutar `node --check admin.js` y `node --check main.js`.

## Escala del admin y selector de período Pedix (2026-11-04)

### Escala del panel (escritorio)

- `admin-main` pasó a `min(1680px, 96%)`, con menos padding lateral, para aprovechar el ancho de pantalla.
- Texto base en 16 px, campos más cómodos, botones con altura mínima de 40 px y tabs más grandes.
- Pedidos: tarjetas con más padding, número de pedido y total destacados, columnas de mínimo 300 px que se reparten el ancho disponible.
- El tablero usa altura calculada con `vh`, con scroll vertical interno por columna.
- La barra horizontal del tablero ahora mide 12 px y usa los colores del tema oscuro; aparece solo cuando las columnas no entran.
- Carta y Envíos conservan sus grillas y se adaptan al contenedor más ancho.

### Selector de período

- Se reemplazó la barra anterior por: selector `Por día / Por semana / Por mes / Personalizado`, flecha anterior, etiqueta central clickeable y flecha siguiente.
- Etiqueta: `Hoy`/`Ayer`/fecha larga para día; `Esta semana` o rango corto lunes-domingo para semana; `Noviembre 2026` para mes.
- La etiqueta vuelve a hoy al hacer clic. La flecha siguiente se bloquea cuando el período siguiente sería futuro.
- Personalizado muestra únicamente los inputs Desde/Hasta, con límite máximo en hoy.
- Todos los cálculos de fecha se hacen en `America/Argentina/Buenos_Aires`; el filtrado, los contadores, el tablero, la lista y el CSV usan el mismo rango.
- Sucursal, Tablero/Lista y Exportar CSV quedan a la derecha; las pestañas Todos / Para llevar / Delivery siguen abajo. En escritorio la barra queda en una fila y en celular se apila.

### Cómo probar

1. Verificar que el panel use el ancho disponible y que Carta/Envíos no se rompan.
2. En Pedidos, revisar columnas, scroll horizontal fino, scroll vertical por columna y que la página no obligue a bajar en escritorio.
3. Probar día, semana, mes y personalizado; comprobar etiquetas, flechas y bloqueo de fechas futuras.
4. Confirmar que el CSV exporta solo el rango visible.
5. Probar la barra en celular.
6. Ejecutar `node --check admin.js`.

## Admin por sucursal (2026-11-04)

### Migración 017

Archivo nuevo: `supabase/migrations/017_admin_por_sucursal.sql`. **No fue ejecutado.** La migración 016 ya está aplicada en la base real y no se reaplica.

- `public.admins`: agrega `rol` (`dueno`|`sucursal`) y `sucursal_id`. Los admins existentes quedan `dueno` con `sucursal_id = null`.
- Checks: `rol` válido; `dueno` exige `sucursal_id null`; `sucursal` exige una de las dos sucursales reales (`maestro-quiroga`, `intendente-lascano`).
- Los admins se gestionan solo por SQL/Auth. No hay pantalla ni permisos directos para `anon`/`authenticated`, así que un admin de sucursal no puede crear admins ni cambiar su `sucursal_id`.
- Funciones `security definer` con `search_path = ''`: `es_admin()` se mantiene, se agregan `es_dueno()`, `sucursal_admin()` y `mi_rol()`.
- `mi_rol()` devuelve `{rol, sucursal_id}` del JWT y tiene `execute` para `authenticated`. `admin.js` sigue validando el acceso con `rpc('es_admin')` y no consulta la tabla `admins` con `.from('admins')`, así que `admins` queda sin acceso directo.
- Políticas viejas con `es_admin()` reemplazadas o eliminadas: `Pedidos lectura/edicion admin`; `Zonas alta/edicion/baja admin`; `Tramos alta/edicion/baja admin`; `Carta alta/edicion/baja admin`; `Config alta/edicion/baja admin`; `Clientes lectura admin`; `Imagenes alta/edicion/baja admin` de `storage.objects`.
- RLS por sucursal:
  - `pedidos`: SELECT/UPDATE solo para el dueño o para la sucursal del admin. UPDATE con `USING` y `WITH CHECK` iguales. El grant por columnas (`estado`, `pagado`, `pagado_en`) se mantiene como ya está en la base.
  - `zonas_envio` y `tramos_envio`: se mantiene la lectura pública (`Zonas lectura publica` y `Tramos lectura publica`) porque `main.js` las lee con `anon`; no se revoca `select` a `anon`. Solo se restringe INSERT/UPDATE/DELETE: el dueño edita todo, el admin de sucursal solo filas de su sucursal y las globales (`sucursal_id null`) solo las toca el dueño. Se eliminan las políticas `Zonas lectura admin` y `Tramos lectura admin`.
  - `carta`, `config_negocio`, `clientes` y Storage: lectura/escritura según corresponda con `es_dueno()`; `clientes` pasa de `es_admin()` a `es_dueno()`.
  - `agotados_sucursal`: SELECT/INSERT/UPDATE/DELETE solo dueño o la sucursal del admin.
- Tabla nueva `public.agotados_sucursal` con PK `(producto_id, sucursal_id)`.
- RPC nueva `public.carta_por_sucursal(p_sucursal_id text)`: devuelve la carta de `carta id = 1` y marca `agotado = true` y `agotado_hasta_nuevo_aviso = true` para los productos agotados de esa sucursal. Usa los mismos nombres de campos que `PM.productoEstaAgotado`.
- `pm_calcular_pedido` se recrea desde la última definición real (013 + ajuste de ofertas de 014 + tramos por cuadras de 015; 016 no la modifica) y el único cambio es el bloque de `agotados_sucursal`. La firma no cambia, así que `crear_pedido` sigue compatible.
- Al final, un bloque `DO` falla si no queda ningún admin con rol `dueno`, lo que revierte la migración. Incluye un rollback manual comentado.

### Dónde viven horarios, cierres, formas de entrega y estado manual

- `admin.js` y `main.js` solo consultan/escriben `config_negocio`, `pedidos`, `tramos_envio` y `zonas_envio`.
- Horarios y cierres: `data/sucursales.json` (`horarios`, `horarioTexto`, `cierreNormal`, `cierreFinde`, `cerradoLunes`) y cálculo en `main.js` (`estaAbiertoAhora`). No hay tabla de Supabase.
- Formas de entrega: botones fijos en `index.html` y `pedidos.modalidad` (`delivery` o `retiro`). No hay tabla ni clave de configuración.
- Estado manual: no existe en el código actual. El estado abierto/cerrado se calcula con los horarios locales.
- `data/config.json` solo contiene negocio y medios de pago.
- Por eso 017 no crea ni modifica tablas para esos conceptos. Si en el futuro pasan a Supabase, necesitarán su propia migración con `sucursal_id` y las mismas políticas.

### Cómo probar

1. **Backup completo de la base antes de aplicar 017.**
2. Aplicar 017 y confirmar que sigue existiendo al menos un admin `dueno`.
3. Con el dueño: ver pedidos de ambas sucursales y actualizar cualquiera.
4. Con un admin de `intendente-lascano`: no debe ver pedidos de `maestro-quiroga`; un UPDATE sobre esos pedidos debe afectar 0 filas.
5. Con un admin de sucursal: intentar editar `carta`, `config_negocio` o subir/borrar imágenes; debe fallar por RLS.
6. Con un admin de sucursal: intentar insertar en `admins` o cambiar su `sucursal_id`; debe fallar por falta de permisos.
7. Cargar un producto en `agotados_sucursal` para Lascano: `carta_por_sucursal('intendente-lascano')` debe marcarlo agotado y `crear_pedido` de Lascano debe rechazarlo; el mismo producto en Maestro Quiroga debe seguir disponible.
8. Verificar que `anon` no pueda leer `pedidos`, `clientes`, `admins` ni `agotados_sucursal`, pero que sí siga leyendo `zonas_envio` y `tramos_envio`.
9. Con un admin, llamar `rpc('mi_rol')` y confirmar que devuelve el `rol` y `sucursal_id` correctos; con un email ajeno debe devolver `null`.

Pendiente de frontend:
- Cambiar la lectura pública de `carta` por `carta_por_sucursal` para que el agotado por sucursal se vea en la web.
- Definir si el admin de sucursal tendrá pantalla para gestionar `agotados_sucursal`.

## Roles en el admin, agotados por sucursal y carta pública (2026-11-04)

### Rol del administrador

- Al iniciar sesión, `admin.js` llama a `rpc('mi_rol')` y guarda `{ rol, sucursal_id }` en estado del módulo.
- `rol = 'dueno'`: mantiene toda la interfaz y permisos visuales anteriores.
- `rol = 'sucursal'`:
  - Se oculta la pestaña Carta.
  - Pedidos: el selector de sucursal queda fijo en la sucursal propia, sin “Todas”.
  - Sonido, badge y título parpadeante solo cuentan pedidos de esa sucursal.
  - Envíos: los datos globales (`sucursal_id = null`) se muestran en solo lectura; los de otras sucursales se ocultan; solo los de su sucursal son editables.
  - Se oculta la configuración general (`metros_por_cuadra`, `tiempo_estimado_entrega`, `descuentos_pago`).
  - El selector de sucursal del formulario de tramos queda fijo en la sucursal propia y deshabilitado.
- Si `mi_rol()` falla o devuelve `null`, el usuario se trata como rol restrictivo sin sucursal: se oculta Carta, no se permite editar Envíos ni la configuración y se muestra “No se pudo verificar tu rol, recargá la página”.
- La seguridad real sigue en RLS; estas reglas son solo de interfaz.

### Mensajes de permisos

- Los rechazos con código `403` o `42501`, y los mensajes de `permission denied` o `row-level security`, muestran “No tenés permiso para hacer esto”.
- Ya no se muestra el mensaje genérico de migraciones 001/002 cuando el error es de permisos.

### Agotados por sucursal en el admin

- Nueva sección **Agotados (hasta que los reactives)** dentro de la pestaña Pedidos.
- Lista los productos de la carta pública que pertenecen a la sucursal elegida.
- El dueño elige la sucursal; el admin de sucursal solo ve la propia.
- Marcar guarda una fila en `agotados_sucursal`; desmarcar la borra.
- El admin escucha cambios de `agotados_sucursal` por Realtime y recarga la lista. Para que lleguen los eventos, `agotados_sucursal` debe estar incluida en la publicación `supabase_realtime` (configuración de Supabase, no SQL del proyecto).
- Los nombres y categorías se escapan con `PM.escaparHtml`.

### Carta pública por sucursal

- `main.js` pide `rpc('carta_por_sucursal', { p_sucursal_id })` al abrir la carta de una sucursal.
- Si la RPC falla, se usa `data/cartas.json` como respaldo.
- La carta se vuelve a pedir:
  - al abrir la carta,
  - al volver a la pestaña (`visibilitychange`),
  - cada 60 segundos mientras la carta o el carrito estén abiertos.
- No hay Realtime de `agotados_sucursal` para el cliente público; el refresco periódico cubre ese caso.
- Si el respaldo local está desactualizado y `crear_pedido` rechaza por agotado:
  - se muestra el mensaje claro con el nombre del producto,
  - se ofrece quitarlo del carrito y reintentar sin perder el resto del pedido,
  - si se acepta, se elimina ese producto, se cierra la ventana de WhatsApp y se mantiene el checkout para reintentar.

### Cómo probar

1. Con un admin `dueno`, verificar que Carta, Pedidos y Envíos funcionan como antes.
2. Con un admin `sucursal`, verificar que Carta está oculta y que Envíos muestra globales en solo lectura y solo permite editar lo propio.
3. Confirmar que el selector de sucursal de Pedidos no tiene “Todas” para el admin de sucursal y que badge, sonido y título solo cuentan sus pedidos.
4. Forzar un fallo de `mi_rol()` y comprobar que aparece el aviso de rol y que la interfaz queda restrictiva.
5. Marcar y desmarcar un producto en “Agotados (hasta que los reactives)” y verificar que `carta_por_sucursal` lo devuelve agotado.
6. Probar con otro admin que el cambio de agotados se refleja por Realtime.
7. Abrir la carta pública de una sucursal y confirmar que usa `carta_por_sucursal`; simular un fallo de la RPC y verificar el respaldo local.
8. Simular un producto agotado con la carta local desactualizada y comprobar que el checkout ofrece quitarlo y reintentar.
9. Ejecutar `node --check admin.js` y `node --check main.js`.
