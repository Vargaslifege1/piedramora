// Verifica que dist/ no tenga rutas rotas ni archivos sensibles. Uso: node tools/verificar-dist.mjs
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, resolve, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const dist = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'dist');
let errores = 0;
const falla = (m) => { errores++; console.error('ERROR: ' + m); };

const listar = (d) => readdirSync(d).flatMap((n) => {
  const p = join(d, n);
  return statSync(p).isDirectory() ? listar(p) : [p];
});
const todos = listar(dist).map((p) => relative(dist, p).split(sep).join('/'));

// Nada sensible
for (const f of todos) {
  if (/\.(md|sql|env|pem|key|bak|log)$/i.test(f) || /^(supabase|docs|tools|backup-|\.)/i.test(f) || /\/\./.test(f)) falla('archivo no permitido: ' + f);
}
for (const f of todos.filter((x) => /\.(html|js|json|css|txt|xml)$/i.test(x) || x === '_headers')) {
  const t = readFileSync(join(dist, f), 'utf8');
  if (/service_role/i.test(t)) falla('"service_role" en ' + f);
  for (const m of t.matchAll(/eyJ[\w-]+\.([\w-]+)\.[\w-]+/g)) {
    try { if (JSON.parse(Buffer.from(m[1], 'base64url').toString()).role !== 'anon') falla('JWT no-anon en ' + f); } catch { /* no es JWT */ }
  }
}

// Rutas referenciadas
const EXT = '(?:html|js|css|json|webp|png|jpe?g|ico|svg|gif|mp3|ogg|wav|txt|xml|woff2?)';
const reExt = new RegExp('[.]' + EXT + '$', 'i');
const refs = new Map();
const agregar = (origen, ruta) => {
  ruta = ruta.split('#')[0].split('?')[0].trim();
  if (!ruta || /^(https?:|\/\/|data:|mailto:|tel:|javascript:|blob:)/i.test(ruta)) return;
  try { ruta = decodeURI(ruta); } catch { /* se deja tal cual */ }
  ruta = ruta.replace(/^[.]?\//, '');
  if (!refs.has(ruta)) refs.set(ruta, origen);
};
for (const f of ['index.html', 'admin.html']) {
  const t = readFileSync(join(dist, f), 'utf8');
  for (const m of t.matchAll(/(?:href|src|content)=["']([^"']+)["']/g)) if (reExt.test(m[1].split(/[?#]/)[0])) agregar(f, m[1]);
}
const reJs = new RegExp('[\'"`]((?:[.]?/)?(?:assets|data|js)/[^\'"`$]*?[.]' + EXT + ')[\'"`]', 'gi');
for (const f of ['main.js', 'admin.js', 'js/core/utils.js', 'js/core/carta-ids.js']) {
  const t = readFileSync(join(dist, f), 'utf8');
  for (const m of t.matchAll(reJs)) agregar(f, m[1]);
}
const reJson = new RegExp('"((?:[.]?/)?(?:assets|data|js)/[^"]*?[.]' + EXT + ')"', 'gi');
for (const f of todos.filter((x) => x.startsWith('data/') && x.endsWith('.json'))) {
  const t = readFileSync(join(dist, f), 'utf8');
  for (const m of t.matchAll(reJson)) agregar(f, m[1]);
}
for (const [ruta, origen] of refs) if (!existsSync(join(dist, ruta))) falla(`ruta rota "${ruta}" (referenciada en ${origen})`);

console.log(`${todos.length} archivos en dist/, ${refs.size} rutas verificadas.`);
console.log(errores ? `${errores} problema(s).` : 'OK: sin rutas rotas ni archivos sensibles.');
process.exit(errores ? 1 : 0);
