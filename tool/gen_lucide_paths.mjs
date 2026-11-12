// Génère lib/core/theme/lucide_paths.dart : les tracés SVG des icônes Lucide
// citées dans lib/core/theme/app_icons.dart (un `LucidePaths.<nom>` par icône).
//
//   node tool/gen_lucide_paths.mjs
//
// Les noms viennent des références `LucidePaths.xxx` d'app_icons.dart (camelCase
// → nom Lucide en kebab-case). Les SVG sont lus sur jsdelivr, à la version
// épinglée ci-dessous : changer de version = relancer ce script et relire le
// diff. Les formes (circle, rect…) sont converties en tracés pour que l'app
// n'ait qu'un seul type de primitive à dessiner.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const LUCIDE_VERSION = '1.67.0';
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const iconsFile = join(root, 'lib/core/theme/app_icons.dart');
const outFile = join(root, 'lib/core/theme/lucide_paths.dart');

const kebab = (camel) =>
  camel
    .replace(/([a-z])([A-Z])/g, '$1-$2')
    .replace(/([a-zA-Z])(\d)/g, '$1-$2')
    .toLowerCase();

const used = [
  ...new Set(
    [...readFileSync(iconsFile, 'utf8').matchAll(/LucidePaths\.(\w+)/g)].map(
      (m) => m[1],
    ),
  ),
].sort();

const num = (v) => Number.parseFloat(v ?? '0');
const fmt = (n) => String(Math.round(n * 1000) / 1000);

function attrs(source) {
  const out = {};
  for (const m of source.matchAll(/([\w-]+)="([^"]*)"/g)) out[m[1]] = m[2];
  return out;
}

function ellipsePath(cx, cy, rx, ry) {
  return (
    `M${fmt(cx - rx)} ${fmt(cy)}` +
    `a${fmt(rx)} ${fmt(ry)} 0 1 0 ${fmt(2 * rx)} 0` +
    `a${fmt(rx)} ${fmt(ry)} 0 1 0 ${fmt(-2 * rx)} 0`
  );
}

function rectPath(a) {
  const x = num(a.x);
  const y = num(a.y);
  const w = num(a.width);
  const h = num(a.height);
  const rx = Math.min(num(a.rx ?? a.ry), w / 2);
  const ry = Math.min(num(a.ry ?? a.rx), h / 2);
  if (!rx && !ry) return `M${fmt(x)} ${fmt(y)}h${fmt(w)}v${fmt(h)}h${fmt(-w)}z`;
  return (
    `M${fmt(x + rx)} ${fmt(y)}h${fmt(w - 2 * rx)}` +
    `a${fmt(rx)} ${fmt(ry)} 0 0 1 ${fmt(rx)} ${fmt(ry)}` +
    `v${fmt(h - 2 * ry)}` +
    `a${fmt(rx)} ${fmt(ry)} 0 0 1 ${fmt(-rx)} ${fmt(ry)}` +
    `h${fmt(-(w - 2 * rx))}` +
    `a${fmt(rx)} ${fmt(ry)} 0 0 1 ${fmt(-rx)} ${fmt(-ry)}` +
    `v${fmt(-(h - 2 * ry))}` +
    `a${fmt(rx)} ${fmt(ry)} 0 0 1 ${fmt(rx)} ${fmt(-ry)}z`
  );
}

function shapes(svg) {
  const paths = [];
  for (const m of svg.matchAll(
    /<(path|circle|rect|line|polyline|polygon|ellipse)\b([^>]*?)\/?>/g,
  )) {
    const [, tag, rest] = m;
    const a = attrs(rest);
    switch (tag) {
      case 'path':
        paths.push(a.d);
        break;
      case 'circle':
        paths.push(ellipsePath(num(a.cx), num(a.cy), num(a.r), num(a.r)));
        break;
      case 'ellipse':
        paths.push(ellipsePath(num(a.cx), num(a.cy), num(a.rx), num(a.ry)));
        break;
      case 'rect':
        paths.push(rectPath(a));
        break;
      case 'line':
        paths.push(`M${a.x1} ${a.y1}L${a.x2} ${a.y2}`);
        break;
      case 'polyline':
      case 'polygon': {
        const pts = a.points.trim().split(/[\s,]+/);
        let d = `M${pts[0]} ${pts[1]}`;
        for (let i = 2; i < pts.length; i += 2) d += `L${pts[i]} ${pts[i + 1]}`;
        paths.push(tag === 'polygon' ? `${d}z` : d);
        break;
      }
    }
  }
  return paths;
}

const entries = [];
const failures = [];
for (const name of used) {
  const slug = kebab(name);
  const url = `https://cdn.jsdelivr.net/npm/lucide-static@${LUCIDE_VERSION}/icons/${slug}.svg`;
  const res = await fetch(url);
  if (!res.ok) {
    failures.push(`${name} (${slug}): HTTP ${res.status}`);
    continue;
  }
  const paths = shapes(await res.text());
  if (paths.length === 0) {
    failures.push(`${name} (${slug}): aucun tracé`);
    continue;
  }
  entries.push({ name, slug, paths });
}

if (failures.length > 0) {
  console.error(`Échec :\n  ${failures.join('\n  ')}`);
  process.exit(1);
}

const lines = [
  '// GÉNÉRÉ par tool/gen_lucide_paths.mjs — ne pas éditer à la main.',
  `// Source : lucide-static ${LUCIDE_VERSION} (licence ISC).`,
  '',
  '/// Tracés SVG des icônes Lucide (grille de 24), un `d` par élément.',
  '/// Consommés par `AppIcons` via `StrokeIconData`.',
  'abstract final class LucidePaths {',
];
for (const { name, slug, paths } of entries) {
  lines.push(`  /// \`${slug}\``);
  lines.push(`  static const ${name} = <String>[`);
  for (const p of paths) lines.push(`    '${p}',`);
  lines.push('  ];');
}
lines.push('}', '');
writeFileSync(outFile, lines.join('\n'));
console.log(`${entries.length} icônes écrites dans ${outFile}`);
