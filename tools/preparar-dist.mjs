// Regenera dist/ con SOLO lo que el sitio publico usa. Uso: node tools/preparar-dist.mjs
import { rmSync, mkdirSync, cpSync, existsSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, resolve, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(raiz, 'dist');

// Lista blanca: archivos y carpetas que se publican.
const ARCHIVOS = ['index.html', 'admin.html', 'main.js', 'admin.js', 'style.css', 'admin.css',
  'robots.txt', 'sitemap.xml', '_headers', 'apple-touch-icon.png'];
const CARPETAS = ['js', 'data', 'assets'];
const PATRONES_RAIZ = [/^favicon.*$/i, /^android-chrome.*$/i];
// Nunca se copia aunque este dentro de una carpeta permitida.
const EXCLUIR = [/\.md$/i, /\.sql$/i, /^backup-/i, /^\.(claude|cursor|git|tmp)$/i, /^(supabase|docs|tools)$/i, /^thumbs\.db$/i, /^\.ds_store$/i];
const excluido = (nombre) => EXCLUIR.some((r) => r.test(nombre));

rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });

const copiar = (rel) => {
  const origen = join(raiz, rel);
  if (!existsSync(origen)) { console.warn('Falta (se omite): ' + rel); return; }
  cpSync(origen, join(dist, rel), { recursive: true, filter: (src) => !excluido(basename(src)) });
};

ARCHIVOS.forEach(copiar);
CARPETAS.forEach(copiar);
readdirSync(raiz).filter((n) => statSync(join(raiz, n)).isFile() && PATRONES_RAIZ.some((r) => r.test(n))).forEach(copiar);

console.log('dist/ regenerado.');
