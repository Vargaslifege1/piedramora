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

## Fase 3A: cupones (018)

Archivo nuevo: `supabase/migrations/018_cupones.sql`. **No fue ejecutado.** Hacer backup completo de la base antes de aplicarlo.

- Tablas `cupones`, `cupon_usos` y `cupon_intentos`. Cupones y usos solo los ve el dueño; los intentos no tienen acceso.
- En `pedidos`: `cupon_codigo` y `descuento_cupon`. `grant select` de esas columnas para `authenticated`. El grant de UPDATE no se toca.
- `valida_cupon` y `crear_pedido` con `p_cupon`. El mínimo de compra se muestra sin decimales (`$10.000`).
- `pm_calcular_pedido` no se modifica: sigue la de 017.
- `main.js` ya manda el cupón: ver sección "Fase 3C: cupón en el checkout" más abajo (hecha).

## Fase 3C: cupón en el checkout (frontend, 018 ya aplicada)

Archivos tocados: `index.html`, `style.css`, `main.js`. No se tocó SQL.

- Campo "¿Tenés un código?" + botón "Aplicar" arriba del resumen de totales (reusa `.pedix-input-wrap`/`.pedix-btn-buscar`/`.pedix-ayuda-texto` ya usados por el buscador de dirección). Nueva línea `#linea-cupon` en `.checkout-totales` con botón "✕" para quitarlo.
- `validarCuponActual()` llama a `rpc('valida_cupon', {...})`. Exige teléfono (mínimo 8 dígitos) y sucursal cargada antes de llamar al servidor; si faltan, avisa sin pegarle al RPC.
- Se revalida solo (debounce de 500 ms) cuando ya hay un cupón aplicado y cambia: medio de pago, tipo de entrega/modalidad, teléfono o el carrito (hooks en `actualizarEtiquetasPago`'s listener, `cotizarEnvioCheckout`, `renderizarListaCheckout` y el input de teléfono). Si deja de ser válido, se quita y se avisa con el mensaje del servidor.
- La vista previa del total (`actualizarResumenPago`) resta el descuento de `valida_cupon` en vez de sumarlo al de medio de pago (el cliente no sabe si el cupón es acumulable; el servidor decide el ganador real). Queda comentado en el código que el total final siempre lo fija `crear_pedido`.
- Al enviar, se manda `p_cupon` a `crear_pedido`. Si el servidor rechaza el pedido por un motivo propio del cupón (mensajes de `pm_validar_cupon`: no válido, vencido, ya usado, mínimo de compra, solo primera compra, sin usos disponibles, pierde contra el descuento por pago, no vigente), se avisa en el checkout con `mostrarEstadoCupon` (sin `alert()`) y se reintenta `crear_pedido` una sola vez sin el cupón, con la misma `idempotency_key`, sin perder el carrito. Cualquier otro rechazo sigue el flujo existente (agotado / confirmar envío sin registrar).
- El mensaje de WhatsApp y el modal "Pedido recibido" siguen usando únicamente el `descuento`/`total` que devuelve `crear_pedido`; solo cambia la etiqueta de la línea de descuento a "Cupón `<código>`" cuando el pedido guardado efectivamente se mandó con cupón (dato que ya tiene el cliente, no un cálculo nuevo).
- Fallback local (Supabase caído o el pedido no se pudo registrar ni con reintento): el total/descuento mostrado sigue siendo solo el de medio de pago (`totalesCliente`, sin cambios), nunca con el descuento de cupón calculado en el navegador. Si había un cupón intentado, el mensaje de WhatsApp agrega una línea aclarando que no se aplicó.
- `node --check main.js` sin errores.

### Cómo probar

1. Cargar un producto al carrito, completar teléfono y sucursal. Escribir `LICHI`, tocar "Aplicar" → mensaje "Cupón aplicado." en verde, aparece la línea "Cupón LICHI: -$N" y el total de vista previa baja. Confirmar el pedido y revisar que el modal y el mensaje de WhatsApp muestran el total/descuento que devolvió el servidor.
2. Escribir un código inexistente → mensaje de error del RPC, sin aplicar nada.
3. Con `LICHI` aplicado, cambiar el medio de pago a uno con más descuento que el cupón → se revalida solo, el servidor devuelve que gana el medio de pago, y el cupón se quita con aviso.
4. Borrar el teléfono y tocar "Aplicar" → "Completá tu teléfono primero.", sin llamar al servidor.

## Fase 3B: pestaña "Cupones" en el admin (018 ya aplicada)

Archivos tocados: `admin.html`, `admin.js`, `admin.css`. No se tocó SQL ni migraciones.

- Pestaña "Cupones" visible solo si `adminRol === 'dueno'` y el rol se verificó (`puedeVerCupones()`). Si `mi_rol` falla, queda oculta; `mostrarVistaAdmin('cupones')` redirige a Pedidos si no hay permiso.
- Listado desde `cupones` (RLS `es_dueno`): código, "10%" o "$2.000", estado, vigencia, `usos / máximo` y total descontado.
- Usos y total: `cupon_usos` con `pedidos(estado)` embebido; se agrupa en el cliente excluyendo pedidos `cancelado`. Si el embed falla, se cuentan todos y se muestra un aviso visible ("incluyen pedidos cancelados").
- Estado solo visual, comparando instantes con la hora del navegador: pausado > vencido > agotado > programado (inicio futuro) > activo. El servidor sigue decidiendo la validez real.
- Fechas: se muestran con `timeZone: 'America/Argentina/Buenos_Aires'` y se envían con offset `-03:00`.
- Formulario crear/editar: código en mayúsculas y sin espacios (deshabilitado al editar), tipo, valor (porcentaje 1-100, monto entero > 0), activo, fechas, usos máximos, usos por cliente, compra mínima, primera compra, sucursal (Todas/Lascano/Maestro Quiroga → `null` o un solo elemento), modalidad (Todas/delivery/retiro) y acumulable con pago. Si el cupón ya tiene usos, se muestra "Los usos anteriores conservan el descuento que tuvieron".
- Errores del servidor traducidos: `23505` (código duplicado), `23514` (check constraints por nombre), `23503` ("Tiene usos registrados: pausalo en vez de borrarlo"), 403/42501 ("No tenés permiso para hacer esto.").
- Acciones: Pausar/Activar con un clic, Borrar con `confirm()` (avisa si hay usos y sugiere pausar). Nunca se borran usos desde el cliente.
- Todo lo dinámico pasa por `escaparHtml`. `node --check admin.js` sin errores.

### Cómo probar

1. Entrar al admin como dueño → aparece la pestaña "Cupones". Entrar como admin de sucursal (o forzar un fallo de `mi_rol`) → no aparece.
2. "Nuevo cupón": crear `PRUEBA10` (10%). Repetir el código → "Ya existe un cupón con ese código." Probar porcentaje 101 y vencimiento anterior al inicio → errores claros en el formulario.
3. Editar un cupón: el código está bloqueado. Si ya tiene usos, aparece la nota de usos anteriores.
4. Pausar/Activar con un clic; crear uno con inicio futuro (Programado) y otro ya vencido (Vencido); uno con usos máximos 1 y un pedido aplicado (Agotado).
5. Usar un cupón en un pedido y cancelar ese pedido → el contador de usos y el total descontado no lo cuentan.
6. Borrar un cupón sin usos → se borra. Borrar uno con usos → falla con "Tiene usos registrados: pausalo en vez de borrarlo."

### Ajuste de UX en Cupones (formulario)

Archivos tocados: `admin.html`, `admin.js`, `admin.css`. Sin SQL.

- El formulario se cierra y vuelve a la lista (scroll suave a `#cupones-lista`) al guardar con éxito y al cancelar. Si el guardado falla, queda abierto con el error.
- "Cancelar" y "✕" arriba del formulario (junto al título, que cambia entre "Nuevo cupón" y "Editar cupón"), además del "Cancelar" de abajo. Ninguno tiene `hidden` ni CSS que lo oculte.
- Escape cierra el formulario si el foco está dentro. Tiene prioridad sobre los modales.
- Al abrir el formulario (nuevo o editar) se hace scroll suave hasta él.
- `node --check admin.js` sin errores.

Cómo probar: abrir "Nuevo cupón" (scroll al formulario), cancelar con los tres botones y con Escape; guardar uno válido (cierra y baja a la lista); repetir un código (queda abierto con el error).

## Fase 3D-1: fidelidad y premios (base de datos, migración 019 — aplicada)

Archivo nuevo: `supabase/migrations/019_fidelidad_premios.sql` (ya aplicada en producción). Esta fase no tocó el frontend (ver 3D-2).

- Ciclo de 10 pedidos entregados: 5.º → 30% en un pedido futuro (sin tope); 10.º → Cheeseburger gratis (`burger_cheeseburger`, variación SIMPLE). Vencen a 30 días, un solo uso.
- Cuentan solo pedidos entregados con `sincronizado` distinto de false y `pedidos.subtotal >= 10000` (subtotal de productos, antes de descuentos y sin envío).
- Config en `config_negocio.fidelidad` (solo reglas; escritura solo `es_dueno()` desde la 017). `pm_fidelidad_config()` valida y, si falta/está mal/inactiva, el programa queda inactivo.
- Tablas/columnas: `premios` (RLS: solo el dueño lee, sin escritura directa), `fidelidad_intentos` (anti-spam, sin acceso), `pedidos.fidelidad_contado`, `pedidos.premio_id`, `clientes.fidelidad_pedidos`.
- Trigger `pm_pedidos_actualizar_clientes()` extendido (solo se agregó el bloque de fidelidad al pasar a `entregado`, no por cambio de teléfono). Trigger nuevo `pedidos_liberar_premio`: cancelar libera el premio si no venció.
- RPC públicas: `mis_premios(p_telefono)` y `mi_progreso_fidelidad(p_telefono)` (anti-spam 10/10 min por teléfono, 30/10 min por IP, 100/5 min global; error genérico).
- `crear_pedido` pasa a 14 argumentos (`p_premio_id uuid default null`); con premio se ignoran cupón y descuento por pago; premio + cupón se rechaza; el canje bloquea la fila (`FOR UPDATE`) y marca el premio usado en la misma transacción.
- Limitaciones documentadas en la migración: el contador no se resta al revertir/cancelar un pedido ya contado; sin backfill de pedidos históricos; si falla la acreditación se loguea un WARNING y no se bloquea el cambio de estado.
- La migración incluye rollback comentado y casos de prueba (a–q).
- Frontend hecho en 3D-2 (ver abajo). Panel del dueño hecho en 3D-3 (ver abajo).

## Registro de clientes (migración 020 — aplicada)

Archivo nuevo: `supabase/migrations/020_registro_clientes.sql` (ya aplicada en producción). No tocó el trigger de clientes.

- `clientes`: columnas nuevas `apellido`, `acepta_promos` (default false), `acepta_promos_en`, `registrado_en`, `origen` (`registro`|`pedido`, default `pedido`). Lectura solo `es_dueno()` (011 + 017); anon sin acceso.
- `registrar_cliente(nombre, apellido, telefono, acepta_promos)`: upsert que no pisa el nombre de quien ya pidió; `acepta_promos` solo sube de false a true. Devuelve solo `{ok:true}` o un mensaje genérico.
- `borrar_mis_datos(telefono)`: quita el consentimiento y borra el registro si nunca pidió; no borra pedidos. Sin verificación de titularidad del teléfono (limitación documentada).
- Anti-spam compartido en `registro_intentos` (5/10 min por teléfono, 20/10 min por IP, 100/5 min global).
- `crear_pedido` pasa a 15 argumentos (`p_acepta_promos boolean default null`): con `true` registra el consentimiento sin tocar nombre ni otras columnas.
- Para el CRM: `origen` no cambia si el cliente se registra y después pide; para frecuentes/inactivos filtrar por `cantidad_pedidos_entregados > 0`.
- Rollback: dropear las columnas borra los consentimientos (backup antes). Incluye casos de prueba a–i.

## Fase 3D-2: tarjeta de progreso, registro y canje de premios en el sitio (2026-11-05)

Frontend de la fidelidad. Migraciones 019 y 020 ya aplicadas; no hubo cambios de base de datos.

- `index.html`: tarjeta `#fidelidad-tarjeta` (vistas invitación / formulario de registro / progreso), bloque `#checkout-premios` (radiogroup), línea `#linea-premio` en el resumen, checkbox `#cliente-acepta-promos` y aviso `#pedido-recibido-premio`.
- `main.js` (funciones `fidelidad*`): lee la config, registra con `registrar_cliente`, consulta `mi_progreso_fidelidad` y `mis_premios`, permite "Actualizar" y "Borrar mis datos" (`borrar_mis_datos`). En el checkout, elegir un premio bloquea el cupón y se envían `p_premio_id` y `p_acepta_promos` a `crear_pedido`. El descuento del premio que se ve es solo informativo: el servidor es la autoridad.
- `style.css`: estilos de la tarjeta y del bloque de premios.
- Seguridad: datos escapados con `PM.escaparHtml`/`textContent`, RPC con timeout de 10 s y errores genéricos. Los datos del cliente se guardan solo en el navegador y se olvidan al borrar.
- `node --check main.js` sin errores.

Cómo probar: (1) registrar un cliente con y sin promos y ver el progreso; (2) "Actualizar" y "Borrar mis datos"; (3) con un teléfono con premio, elegirlo en el checkout (el cupón se bloquea y aparece la línea de premio), confirmar y ver el aviso en "Pedido recibido"; (4) con un teléfono sin premios el bloque no aparece.

## Fase 3D-3: sección "Fidelidad" en el admin (2026-11-05)

Panel del dueño para editar `config_negocio.fidelidad`. Sin cambios de base de datos (019/020 ya aplicadas).

- `admin.html` / `admin.js` / `admin.css`: pestaña "Fidelidad" (visible solo con rol `dueno` y `mi_rol` sin error, igual que Cupones). Formulario con "Programa activo", pedido mínimo, ciclo y lista de niveles (en, tipo, valor, tope, producto de la carta guardando el id, días de vencimiento; agregar/quitar, mínimo 1, máximo 20).
- Validación en el cliente espejo de `pm_fidelidad_config` (019); bloquea el guardado con mensaje por nivel. Guarda con upsert por clave `fidelidad`. 403/42501 → "No tenés permiso para hacer esto.". Confirmación al desactivar un programa activo.
- Si la config guardada es inválida: aviso "La configuración actual es inválida: el programa está inactivo" y el formulario se llena con lo legible.
- Producto gratis: ayuda "Se regala la opción más barata, sin costo."; no se ofrecen variaciones.
- Estadística solo lectura desde `premios` (generados, usados, vigentes, vencidos sin usar; por tipo). Si falla, el formulario sigue y se muestra "No se pudieron cargar las estadísticas".
- Todo escapado con `escaparHtml`/`textContent`. `node --check admin.js` sin errores.

Cómo probar: (1) como dueño aparece la pestaña; como sucursal no. (2) Se carga el seed (ciclo 10, niveles 5 y 10). (3) Probar `en` repetido o mayor al ciclo, % 0 o >100, tope 0, días 0/366, producto vacío: bloquea con mensaje. (4) Guardar válido y revisar `config_negocio`; desactivar pide confirmación. (5) Dejar la config inválida desde SQL y recargar: aviso rojo y formulario lleno. (6) Cortar la lectura de `premios` y verificar el mensaje de estadísticas.

## Mejora visual tarjeta de fidelidad (2026-11-05)

Solo frontend (`index.html`, `main.js`, `style.css`); sin SQL ni migraciones.

- Banner destacado: "¡Estás a solo X pedidos de tu <premio>!" / "¡Tu próximo pedido te da <premio>!". Si hay premio disponible (`mis_premios`) pasa a ser el banner principal, con vencimiento en hora Argentina, y el próximo hito queda en texto chico. Textos del servidor siempre con `textContent`.
- Sellos numerados en grilla pareja (hasta 6 por fila, 10 → 5+5), sin scroll horizontal. Hitos: estrella (descuento) o regalo (producto gratis) en SVG inline, lleno si se cumplió y contorno si no. `role="img"` con aria-label generado ("Llevás N de C pedidos. Pedido 5: ..."); el nombre del producto gratis solo se conoce para el próximo hito, el resto dice "producto gratis".
- Acciones: ícono de refrescar y botón ⚙️ arriba a la derecha. El menú ⚙️ tiene "Borrar mis datos" (con la confirmación de siempre); abre con clic/teclado, cierra con Escape, clic afuera o al elegir, y devuelve el foco al ⚙️. No hay "cerrar sesión" en el código, así que no se agregó.
- La animación del premio principal respeta `prefers-reduced-motion`. Registro, caché de 5 min, canje en checkout y los try/catch quedan igual.
- Probar: `node --check main.js`; con cliente registrado ver la tarjeta a 360px, probar con y sin premio, ⚙️ con teclado (Tab, Enter, Escape).

## Barra flotante en píldora (2026-11-05)

Solo frontend (`index.html`, `main.js`, `style.css`); sin SQL ni migraciones.

- `#acceso-carrito-global` ahora es una píldora de 48px centrada abajo: ícono + "Ver pedido (N)" + total. `aria-label` "Ver pedido, N productos, total $X". Mismas condiciones de visibilidad y misma acción (`retomarPedidoGlobal`); textos con `textContent`. Respeta `safe-area-inset-bottom`; máx. 92% de ancho.
- Auto-ocultado: scroll pasivo + `requestAnimationFrame`; baja → se desliza hacia abajo; sube, frena 300 ms, toma foco, se actualiza el carrito (abrir/cerrar/agregar) o se toca "+ Agregar" → reaparece (con pulso). Se oculta con transform/opacity, nunca `display:none`, así nunca queda oculta de forma permanente.
- `prefers-reduced-motion`: sin transición ni animación.
- Padding inferior del body (`tiene-carrito-global`) para no tapar la última fila de "+ Agregar". La píldora solo se muestra con la carta cerrada, por lo que no se superpone con la barra de WhatsApp de la carta.
- Probar: `node --check main.js`; agregar un ítem, cerrar la carta, scrollear arriba/abajo a 360px y 1280px.

## Tarjeta de fidelidad colapsable (2026-11-05)

Solo frontend (`index.html`, `main.js`, `style.css`); sin SQL ni migraciones.

- `#fidelidad-tarjeta` ahora es un acordeón: barra `<button id="fidelidad-barra">` (44px, una línea, ellipsis, flecha que rota; `aria-expanded` + `aria-controls="fidelidad-panel"`) y panel `#fidelidad-panel` con todo el contenido anterior (invitación, formulario, banner, sellos, premios, refrescar y ⚙️).
- Texto de la barra (siempre con `textContent`): premio disponible `🎁 Tenés <premio> · vence dd/mm` (prioridad), progreso `⭐ 6/10 · Te faltan 4 para tu <premio>` (o `¡Tu próximo pedido te da <premio>!`), sin datos `⭐ Pedí 5 veces y ganá 30% · Ver mi progreso` (del primer nivel de la config). Con cliente guardado, los datos se piden en segundo plano con el mismo caché de 5 min; si falla, la barra dice "Mi tarjeta de fidelidad" y reintenta a los 60 s.
- Estado: arranca cerrada; la apertura se guarda en `sessionStorage` (`pm_fidelidad_abierto`) y solo se restaura al recargar en la misma sesión y con cliente guardado. Tocar la barra sin datos abre el panel directo con el formulario.
- Animación de altura/opacidad de 0,22 s (grid 0fr→1fr); con `prefers-reduced-motion` sin transición. Panel cerrado con `visibility:hidden` (no se llega con Tab).
- Intacto: registro, caché, canje en el checkout, try/catch. La tarjeta es parte del flujo de la carta, no se superpone con la píldora flotante.
- Probar: `node --check main.js`; a 360px y 1280px ver la barra cerrada, abrir/cerrar con teclado, con y sin cliente guardado, con y sin premio.

## Agotados con buscador y switches (2026-11-05)

- Pestaña Pedidos > "Agotados (hasta que los reactives)": la grilla de checkboxes pasó a una lista compacta con scroll interno (max 55vh), filas de 52px y switch (`button role="switch"`, `aria-checked`, `aria-label` con el nombre).
- Buscador (sin tildes ni mayúsculas), filtro por categoría, resumen "N agotados" y botón "Ver solo agotados". Agotados primero y resaltados en rojo.
- Un toque guarda al instante en `agotados_sucursal` (upsert/delete como antes). La fila se actualiza al toque, el switch queda deshabilitado mientras guarda y, si falla, se revierte y se muestra el error ("No tenés permiso para hacer esto." ante 403/42501).
- El Realtime sigue recargando la lista; el buscador está fuera de la lista y se conserva el scroll al re-renderizar.
- Sin cambios de SQL/migraciones. Archivos: `admin.html`, `admin.js`, `admin.css`.
- Probar: en 360px buscar "pizza", filtrar por categoría, tocar un switch, cortar la red y verificar que revierte; cambiar un agotado desde otro admin y ver que se actualiza sin perder el texto buscado.

## Carta pública: agotados al final (2026-11-05)

- enderProductosCategoria (main.js) ordena los agotados (globales o por sucursal, vía PM.productoEstaAgotado) al final de cada categoría, con orden estable para el resto. Opacidad de la tarjeta 0.82 → 0.55; la etiqueta AGOTADO y el botón deshabilitado ya existían. Sin cambios de lógica de pedido.


## Cancelados expandible sin scroll horizontal (2026-11-05)

- Reemplaza el intento de panel lateral (revertido). Cancelados vuelve a ser la 6ª columna del tablero: cerrada = tira de 56px (título vertical + contador, clic en cualquier parte la abre); abierta = 280px con título horizontal y botón ✕ (`aria-expanded`, `aria-label`) en el encabezado.
- Las otras 5 columnas usan `flex: 1 1 0; min-width: 180px` y se achican solas, con transición corta de ancho (sin transición con `prefers-reduced-motion`). Tarjetas con ellipsis en top/cliente/meta, `min-width: 0` y botones que envuelven; Cancelados con opacidad 0.8 y sin botón de avanzar.
- Estado en `sessionStorage` (`pm_cancelados_abierto`, por defecto cerrada). El re-render por realtime/filtros lo respeta y conserva el scroll vertical de Cancelados y el horizontal del tablero.
- Celular (≤720px): carril horizontal; abierta ocupa 85vw y se hace `scrollIntoView` suave; se cierra con el mismo botón.
- Sin SQL/migraciones. Archivos: `admin.js`, `admin.css` (y `admin.html` vuelve a su estado previo).
- Probar: `node --check admin.js`; a 1280px+ abrir/cerrar Cancelados sin barra horizontal; recargar (misma sesión) y ver que recuerda; cancelar un pedido con la columna abierta; a 360px abrir y ver el scroll suave.
