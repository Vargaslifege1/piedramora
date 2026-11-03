import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, resolve } from 'node:path';

globalThis.window = globalThis;

const raiz = resolve(dirname(fileURLToPath(import.meta.url)), '..');
await import(pathToFileURL(resolve(raiz, 'js/core/utils.js')).href);

const PM = globalThis.PM;

const casos = [
  {
    nombre: 'antes de "desde"',
    producto: {
      oferta_desde: '2026-11-03T10:00:00-03:00',
      oferta_hasta: '2026-11-03T20:00:00-03:00'
    },
    ahora: '2026-11-03T09:59:00-03:00',
    esperado: false
  },
  {
    nombre: 'dentro del rango',
    producto: {
      oferta_desde: '2026-11-03T10:00:00-03:00',
      oferta_hasta: '2026-11-03T20:00:00-03:00'
    },
    ahora: '2026-11-03T15:00:00-03:00',
    esperado: true
  },
  {
    nombre: 'justo después de "hasta"',
    producto: {
      oferta_desde: '2026-11-03T10:00:00-03:00',
      oferta_hasta: '2026-11-03T20:00:00-03:00'
    },
    ahora: '2026-11-03T20:00:01-03:00',
    esperado: false
  },
  {
    nombre: 'sin fechas',
    producto: {},
    ahora: '2026-11-03T15:00:00-03:00',
    esperado: true
  }
];

let fallos = 0;

for (const caso of casos) {
  const ahoraMs = Date.parse(caso.ahora);
  const resultado = PM.ofertaVigente(caso.producto, ahoraMs);
  const ok = resultado === caso.esperado;
  if (!ok) fallos += 1;
  console.log(`${ok ? 'OK' : 'FALLA'} - ${caso.nombre}: esperado ${caso.esperado}, obtenido ${resultado}`);
}

if (fallos > 0) {
  console.error(`\n${fallos} caso(s) fallaron.`);
  process.exit(1);
}

console.log('\nTodos los casos pasaron.');
