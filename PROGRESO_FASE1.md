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
- Pendiente: bandeja de pedidos y sección **Envíos** en el admin, y guardar los SQL de `tramos_envio` y `cotizar_envio` como **migración 015**.
