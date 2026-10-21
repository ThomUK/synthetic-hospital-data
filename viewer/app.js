import { buildIndex, releaseUrl, sampleUrl, previewPath, formatCell, fmtBytes, fmtInt, parseRoute, routeFor, isNumericType, assetName } from './engine.js?v=dev';

const DATA_ROOT = '../data/v2/';
const RELEASE_PAGE = 'https://github.com/ThomUK/synthetic-hospital-data/releases/tag/';
const view = document.getElementById('view');
const status = document.getElementById('status');
let index = null;
const previews = new Map();

function el(tag, attrs = {}, ...children) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') e.className = v;
    else if (k === 'html') e.innerHTML = v;
    else e.setAttribute(k, v);
  }
  for (const c of children.flat()) if (c != null) e.append(c.nodeType ? c : document.createTextNode(String(c)));
  return e;
}

function setStatus(msg) { status.textContent = msg || ''; status.hidden = !msg; }

async function loadIndex() {
  const r = await fetch(DATA_ROOT + 'manifest.json');
  if (!r.ok) throw new Error(`manifest: HTTP ${r.status}`);
  index = buildIndex(await r.json());
}

async function loadPreview(key) {
  if (previews.has(key)) return previews.get(key);
  const r = await fetch(previewPath(DATA_ROOT, key));
  if (!r.ok) throw new Error(`preview ${key}: HTTP ${r.status}`);
  const p = await r.json();
  previews.set(key, p);
  return p;
}


function findTable(key) {
  for (const g of index.groups) for (const t of g.tables) if (t.key === key) return { table: t, group: g };
  return null;
}

function renderIndex() {
  document.title = 'Synthetic Hospital Data: table viewer';
  view.replaceChildren();
  for (const g of index.groups) {
    view.append(el('h2', {}, g.label), el('p', { class: 'blurb' }, g.blurb));
    const tbody = el('tbody');
    for (const t of g.tables) {
      tbody.append(el('tr', {},
        el('td', {}, el('a', { class: 'tbl', href: routeFor(t.key) }, t.name)),
        el('td', { class: 'desc' }, t.description),
        el('td', { class: 'num' }, t.sample ? fmtInt(t.sample.rows) : '–'),
        el('td', { class: 'num' }, t.full ? fmtInt(t.full.rows) : '–'),
        el('td', { class: 'num' }, t.full ? fmtBytes(t.full.bytes) : '–'),
        el('td', { class: 'num' }, t.full ? String(t.full.files.length) : '–')));
    }
    view.append(el('table', { class: 'index' },
      el('thead', {}, el('tr', {},
        el('th', {}, 'Table'), el('th', { class: 'desc' }, 'What it is'),
        el('th', { class: 'num' }, 'Sample rows'), el('th', { class: 'num' }, 'Full rows'),
        el('th', { class: 'num' }, 'Full size'), el('th', { class: 'num' }, 'Files'))),
      tbody));
  }
  if (index.extras.length) {
    view.append(el('h2', {}, 'Other files'));
    const ul = el('ul');
    for (const x of index.extras) {
      const f = (x.sample || x.full).files[0];
      ul.append(el('li', {}, el('a', { href: sampleUrl(f) }, x.key), ` (${fmtBytes((x.sample || x.full).bytes)})`));
    }
    view.append(ul);
  }
  view.append(el('p', { class: 'blurb' },
    `Totals: sample ${fmtBytes(index.totals.sample_bytes)} in this site, full set ${fmtBytes(index.totals.full_bytes)} on the `,
    el('a', { href: RELEASE_PAGE + index.version, target: '_blank', rel: 'noopener' }, 'GitHub release'), '. ',
    el('a', { href: DATA_ROOT + 'manifest.json' }, 'manifest.json'), ' lists every file with its checksum.'));
}

function downloadLinks(t, part) {
  const box = el('div', { class: 'downloads' });
  const e = t[part];
  if (!e) return box;
  for (const f of e.files) {
    const name = part === 'full' ? assetName(f) : f.split('/').slice(-1)[0];
    const href = part === 'full' ? releaseUrl(index.version, f) : sampleUrl(f);
    box.append(el('a', { href, target: '_blank', rel: 'noopener' }, name));
  }
  return box;
}

async function renderTable(key) {
  const hit = findTable(key);
  if (!hit) { view.replaceChildren(el('p', {}, `No table called ${key}. `, el('a', { href: '#/' }, 'Back to the index'))); return; }
  const { table: t, group: g } = hit;
  document.title = `${t.name}: table viewer`;
  view.replaceChildren();
  view.append(el('p', { class: 'crumbs' }, el('a', { href: '#/' }, 'All tables'), ' › ', g.label, ' › ', t.name));
  view.append(el('h2', {}, t.key));
  if (t.description) view.append(el('p', { class: 'blurb' }, t.description));

  const meta = el('div', { class: 'meta' },
    el('span', {}, 'Sample rows: ', el('b', {}, t.sample ? fmtInt(t.sample.rows) : '–')),
    el('span', {}, 'Full rows: ', el('b', {}, t.full ? fmtInt(t.full.rows) : '–')),
    el('span', {}, 'Full size: ', el('b', {}, t.full ? fmtBytes(t.full.bytes) : '–')),
    el('span', {}, 'Full-set files: ', el('b', {}, t.full ? t.full.files.length : '–')));
  const panel = el('div', { class: 'panel' }, meta);
  if (t.sample) panel.append(el('p', { class: 'blurb' }, 'Sample, from this site:'), downloadLinks(t, 'sample'));
  if (t.full) panel.append(el('p', { class: 'blurb' }, 'Full set, from the GitHub release:'), downloadLinks(t, 'full'));
  view.append(panel);

  const holder = el('div', {}, el('p', { class: 'status' }, 'Loading preview…'));
  view.append(holder);
  if (!t.sample) { holder.replaceChildren(el('p', { class: 'status' }, 'This table is not in the sample, so there is no preview.')); return; }
  let p;
  try { p = await loadPreview(key); } catch (e) { holder.replaceChildren(el('p', { class: 'status' }, `Could not load the preview: ${e.message}`)); return; }
  if (parseRoute(location.hash).key !== key) return; // navigated away meanwhile

  const cols = el('div', { class: 'cols' }, p.columns.map((c) => el('span', {}, c.name, el('i', {}, c.type))));
  const head = el('tr', {}, el('th', { class: 'rownum' }, '#'), p.columns.map((c) => el('th', {}, c.name, el('small', {}, c.type))));
  const body = el('tbody');
  p.rows.forEach((row, i) => {
    const tr = el('tr', {}, el('td', { class: 'rownum' }, i + 1));
    row.forEach((v, j) => {
      const type = p.columns[j].type;
      const s = formatCell(v, type);
      const cls = s === null ? 'null' : (isNumericType(type) ? 'num' : '');
      tr.append(el('td', { class: cls, title: s === null ? '' : s }, s === null ? 'null' : s));
    });
    body.append(tr);
  });
  holder.replaceChildren(
    el('p', { class: 'blurb' }, `${p.columns.length} columns. Showing the first ${fmtInt(p.rows.length)} of ${fmtInt(p.rows_total)} sample rows. Scroll sideways for more columns.`),
    cols,
    el('div', { class: 'grid-wrap' }, el('table', { class: 'grid' }, el('thead', {}, head), body)));
}

async function route() {
  const r = parseRoute(location.hash);
  if (r.view === 'table') await renderTable(r.key); else renderIndex();
  window.scrollTo(0, 0);
}

(async () => {
  try { await loadIndex(); setStatus(''); } catch (e) { setStatus(`Could not load the dataset manifest: ${e.message}`); return; }
  window.addEventListener('hashchange', route);
  await route();
})();
