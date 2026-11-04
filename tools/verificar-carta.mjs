import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const raiz = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const rutaCarta = resolve(raiz, 'data/cartas.json');
const OFFSET_OFERTA_AR = '-03:00';
const PATRON_ID = /^[a-z0-9_]+$/;
const PATRON_FECHA_ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}-03:00$/;

const errores = [];

function error(mensaje) {
  errores.push(mensaje);
}

function parseFechaOferta(valor) {
  const texto = String(valor == null ? '' : valor).trim();
  if (!texto) return null;
  const ms = Date.parse(texto);
  return Number.isFinite(ms) ? ms : null;
}

function validarFechaOferta(producto, campo) {
  const valor = producto[campo];
  if (valor === undefined || valor === null || valor === '') return null;

  if (typeof valor !== 'string' || !PATRON_FECHA_ISO.test(valor)) {
    error(`"${producto.id}": ${campo} debe ser texto ISO con offset ${OFFSET_OFERTA_AR} (ej: 2026-11-30T23:59:00-03:00). Valor: ${JSON.stringify(valor)}`);
    return null;
  }

  const ms = parseFechaOferta(valor);
  if (ms === null) {
    error(`"${producto.id}": ${campo} no es una fecha válida (${valor}).`);
    return null;
  }

  return ms;
}

let carta;
try {
  carta = JSON.parse(readFileSync(rutaCarta, 'utf8'));
} catch (err) {
  console.error(`No se pudo leer o parsear ${rutaCarta}:`);
  console.error(err.message);
  process.exit(1);
}

if (!Array.isArray(carta.categorias)) error('La carta no tiene un array "categorias".');
if (!Array.isArray(carta.productos)) error('La carta no tiene un array "productos".');

const categorias = new Set();
if (Array.isArray(carta.categorias)) {
  carta.categorias.forEach((cat, indice) => {
    if (!cat || typeof cat !== 'object') {
      error(`Categoría ${indice}: inválida.`);
      return;
    }
    const id = String(cat.id || '').trim();
    if (!id) error(`Categoría ${indice}: falta el id.`);
    else if (!PATRON_ID.test(id)) error(`Categoría "${id}": id inválido (solo minúsculas, números y guiones bajos).`);
    else if (categorias.has(id)) error(`Categoría "${id}" duplicada.`);
    else categorias.add(id);

    if (!String(cat.nombre || '').trim()) error(`Categoría "${id || indice}": falta el nombre.`);
  });
}

const productos = new Set();
let totalOfertas = 0;

if (Array.isArray(carta.productos)) {
  carta.productos.forEach((producto, indice) => {
    if (!producto || typeof producto !== 'object') {
      error(`Producto ${indice}: inválido.`);
      return;
    }

    const id = String(producto.id || '').trim();
    const nombre = String(producto.nombre || '').trim();

    if (!id) error(`Producto ${indice}: falta el id.`);
    else if (!PATRON_ID.test(id)) error(`Producto "${id}": id inválido.`);
    else if (productos.has(id)) error(`Producto "${id}" duplicado.`);
    else productos.add(id);

    if (!nombre) error(`Producto "${id || indice}": falta el nombre.`);

    const categoria = String(producto.categoria || '').trim();
    if (!categoria) error(`Producto "${id}": falta la categoría.`);
    else if (!categorias.has(categoria)) error(`Producto "${id}": categoría inexistente "${categoria}".`);
    else if (id && !id.startsWith(`${categoria}_`)) error(`Producto "${id}": el id debe empezar con "${categoria}_".`);

    if (!producto.precios || typeof producto.precios !== 'object') {
      error(`Producto "${id}": falta el objeto "precios".`);
      return;
    }

    ['delivery', 'mesa'].forEach(modalidad => {
      const precio = Number(producto.precios[modalidad]);
      if (!Number.isFinite(precio) || precio < 0) {
        error(`Producto "${id}": precio ${modalidad} inválido.`);
      }
    });

    const desdeMs = validarFechaOferta(producto, 'oferta_desde');
    const hastaMs = validarFechaOferta(producto, 'oferta_hasta');

    if (desdeMs !== null && hastaMs !== null && hastaMs <= desdeMs) {
      error(`Producto "${id}": el fin de la oferta debe ser posterior al inicio.`);
    }

    const tieneDelivery = producto.delivery_oferta !== undefined && producto.delivery_oferta !== null && producto.delivery_oferta !== '';
    const tieneMesa = producto.mesa_oferta !== undefined && producto.mesa_oferta !== null && producto.mesa_oferta !== '';

    if (tieneDelivery || tieneMesa) {
      totalOfertas += 1;

      if (!tieneDelivery || !tieneMesa) {
        error(`Producto "${id}": si hay oferta deben estar los dos precios (delivery_oferta y mesa_oferta).`);
      } else {
        const deliveryOferta = Number(producto.delivery_oferta);
        const mesaOferta = Number(producto.mesa_oferta);
        const delivery = Number(producto.precios.delivery);
        const mesa = Number(producto.precios.mesa);

        if (!Number.isFinite(deliveryOferta) || deliveryOferta <= 0) {
          error(`Producto "${id}": delivery_oferta debe ser un número mayor a cero.`);
        } else if (deliveryOferta >= delivery) {
          error(`Producto "${id}": delivery_oferta debe ser menor al precio delivery regular.`);
        }

        if (!Number.isFinite(mesaOferta) || mesaOferta <= 0) {
          error(`Producto "${id}": mesa_oferta debe ser un número mayor a cero.`);
        } else if (mesaOferta >= mesa) {
          error(`Producto "${id}": mesa_oferta debe ser menor al precio mesa regular.`);
        }
      }
    }

    if (producto.tipoOferta !== undefined && !['dia', 'semana', 'fecha'].includes(producto.tipoOferta)) {
      error(`Producto "${id}": tipoOferta debe ser "dia", "semana" o "fecha".`);
    }

    if ((tieneDelivery || tieneMesa) && producto.tipoOferta === 'fecha' && hastaMs === null) {
      error(`Producto "${id}": la oferta "Hasta una fecha" necesita oferta_hasta.`);
    }

    if (producto.oferta_hasta && producto.tipoOferta !== 'fecha') {
      error(`Producto "${id}": oferta_hasta solo se usa con tipoOferta "fecha".`);
    }
  });
}

if (errores.length === 0) {
  console.log(`OK: carta válida. ${categorias.size} categorías, ${productos.size} productos, ${totalOfertas} con precio de oferta.`);
} else {
  console.error(`Se encontraron ${errores.length} problema(s):`);
  errores.forEach(mensaje => console.error(`- ${mensaje}`));
}

process.exit(errores.length === 0 ? 0 : 1);
