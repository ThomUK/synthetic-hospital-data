import { TABS, diagramFor, layout, edgeTitle, parseRoute, fmtInt, pct, shortName, BOX } from './engine.js?v=dev';

const ERD = '../data/v2/erd.json';
const VIEWER = '../viewer/#/';
const NS = 'http://www.w3.org/2000/svg';
const $ = (id) => document.getElementById(id);
let erd = null;
let expanded = new Set();
let fit = false;
let showRef = false;

function el(tag, attrs = {}, ...children) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) { if (k === 'class') e.className = v; else e.setAttribute(k, v); }
  for (const c of children.flat()) if (c != null) e.append(c.nodeType ? c : document.createTextNode(String(c)));
  return e;
}
function svgEl(tag, attrs = {}, ...children) {
  const e = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
  for (const c of children.flat()) if (c != null) e.append(c.nodeType ? c : document.createTextNode(String(c)));
  return e;
}


function renderTabs(current) {
  $('tabs').replaceChildren(...TABS.map((t) => el('a', { href: `#/${t.id}`, class: t.id === current ? 'on' : '' }, t.label)));
  $('blurb').textContent = TABS.find((t) => t.id === current).blurb;
}

const tip = $('tip');
function showTip(html, ev) {
  tip.innerHTML = html; tip.hidden = false;
  const x = Math.min(ev.clientX + 14, window.innerWidth - 400); const y = Math.min(ev.clientY + 14, window.innerHeight - 120);
  tip.style.left = `${x}px`; tip.style.top = `${y}px`;
}
function hideTip() { tip.hidden = true; }

function drawBox(b, L, svg) {
  const g = svgEl('g', { class: `box ${b.kind}`, 'data-key': b.key, transform: `translate(${b.x},${b.y})` });
  g.append(svgEl('rect', { class: 'body', width: b.w, height: b.h }));
  g.append(svgEl('line', { x1: 0, y1: BOX.header, x2: b.w, y2: BOX.header, stroke: 'var(--panel-border)' }));
  g.append(svgEl('text', { class: 'title', x: 10, y: 19 }, b.name));
  const rows = b.rowsSample != null ? `${fmtInt(b.rowsSample)} rows` : '';
  g.append(svgEl('text', { class: 'rows', x: b.w - 8, y: 19, 'text-anchor': 'end' }, rows));
  let y = BOX.header + BOX.pad + BOX.row - 4;
  for (const r of b.rows) {
    const c = svgEl('g', { class: `col ${r.isPk ? 'pk' : ''} ${r.isLink ? 'link' : ''}` });
    c.append(svgEl('text', { class: 'name', x: 10, y }, (r.isPk ? '🔑 ' : '') + r.name));
    c.append(svgEl('text', { class: 'type', x: b.w - 8, y, 'text-anchor': 'end' }, r.type.toLowerCase()));
    g.append(c); y += BOX.row;
  }
  if (b.more) { g.append(svgEl('text', { class: 'more', x: 10, y }, `+ ${b.more} more columns (click to expand)`)); y += BOX.row; }
  if (b.sources.length && b.kind === 'main') {
    const s = b.sources.map(shortName).join(', ');
    const t = svgEl('text', { class: 'sources', x: 10, y }, `from: ${s.length > 38 ? s.slice(0, 36) + '…' : s}`);
    t.append(svgEl('title', {}, `Built from: ${b.sources.join(', ')}`));
    g.append(t); y += BOX.row;
  }
  const head = svgEl('rect', { class: 'head', width: b.w - 60, height: BOX.header });
  head.append(svgEl('title', {}, `${b.key}: ${b.expanded ? 'collapse' : 'show all columns'}${b.pkUnique === false ? '. Primary key is not unique in the sample' : ''}`));
  head.addEventListener('click', () => { if (expanded.has(b.key)) expanded.delete(b.key); else expanded.add(b.key); render(); });
  g.append(head);
  const open = svgEl('text', { class: 'open', x: b.w - 8, y: b.h - 2, 'text-anchor': 'end' }, 'rows ↗');
  const link = svgEl('a', { href: VIEWER + b.key, target: '_blank' }); link.append(open); g.append(link);
  g.addEventListener('mouseenter', () => highlight(b.key, svg));
  g.addEventListener('mouseleave', () => highlight(null, svg));
  return g;
}

function highlight(key, svg) {
  for (const e of svg.querySelectorAll('.edge')) {
    if (!key) { e.classList.remove('dim', 'hot'); continue; }
    const on = e.dataset.from === key || e.dataset.to === key;
    e.classList.toggle('hot', on); e.classList.toggle('dim', !on);
  }
  for (const b of svg.querySelectorAll('.box')) b.classList.toggle('selected', b.dataset.key === key);
}

function drawEdge(e) {
  const g = svgEl('g', { class: `edge ${e.link.kind}`, 'data-from': e.from, 'data-to': e.to });
  g.append(svgEl('path', { d: e.path }));
  g.append(svgEl('circle', { cx: e.x2, cy: e.y2, r: 3 }));
  if (e.link.kind === 'fuzzy') {
    const mx = (e.x1 + e.x2) / 2, my = (e.y1 + e.y2) / 2;
    g.append(svgEl('text', { x: mx, y: my - 4, 'text-anchor': 'middle' }, pct(e.link.match_rate)));
  }
  const hit = svgEl('path', { class: 'hit', d: e.path });
  hit.addEventListener('mousemove', (ev) => showTip(`<b>${shortName(e.from)}.${e.link.column}</b> → <b>${shortName(e.to)}.${e.link.to_column}</b><br>${edgeTitle(e.link).split('. ').slice(1).join('. ')}`, ev));
  hit.addEventListener('mouseleave', hideTip);
  g.append(hit);
  return g;
}

function render() {
  const r = parseRoute(location.hash);
  renderTabs(r.tab);
  const ref = showRef || r.tab === 'aggregate'; // aggregates link only to reference tables
  const d = diagramFor(erd, r.tab, { reference: ref });
  const L = layout(d, expanded);
  $('ref').checked = ref; $('ref').disabled = r.tab === 'aggregate';
  const svg = svgEl('svg', { viewBox: `0 0 ${L.width} ${L.height}`, width: L.width, height: L.height, role: 'img', 'aria-label': `ERD for ${r.tab}` });
  for (const c of L.columns) svg.append(svgEl('text', { class: 'group-label', x: c.x, y: BOX.margin + 8 }, c.group));
  const edges = svgEl('g', {}); for (const e of L.edges) edges.append(drawEdge(e)); svg.append(edges);
  const boxes = svgEl('g', {}); for (const b of L.boxes) boxes.append(drawBox(b, L, svg)); svg.append(boxes);
  $('canvas').replaceChildren(svg);
  $('canvas').classList.toggle('fit', fit);
  $('status').textContent = `${d.boxes.filter((b) => b.kind === 'main').length} tables in this layer, ${d.links.length} links drawn (${d.links.filter((l) => l.kind === 'fuzzy').length} fuzzy).`;
  $('expand-all').textContent = expanded.size ? 'Collapse all' : 'Expand all';
  renderSide(r.tab);
}

function renderSide(tab) {
  const rej = erd.rejected.filter((x) => x.from.startsWith(tab + '/'));
  $('rejected').querySelector('div').replaceChildren(rej.length ? el('table', {}, el('thead', {}, el('tr', {}, el('th', {}, 'Column'), el('th', {}, 'Candidate parent'), el('th', {}, 'Why not'))),
    el('tbody', {}, rej.map((x) => el('tr', {}, el('td', {}, el('code', {}, `${shortName(x.from)}.${x.column}`)), el('td', {}, el('code', {}, `${shortName(x.to)}.${x.to_column}`)), el('td', {}, x.reason))))) : el('p', {}, 'None for this layer.'));
  const bad = Object.entries(erd.tables).filter(([k, t]) => k.startsWith(tab + '/') && t.pk.length && t.pk_unique === false);
  $('keys').querySelector('div').replaceChildren(bad.length ? el('ul', {}, bad.map(([k, t]) => el('li', {}, el('code', {}, `${shortName(k)} (${t.pk.join(', ')})`)))) : el('p', {}, 'All unique.'));
  $('basis').textContent = `erd.json built ${erd.built_at} for ${erd.version}: ${erd.basis}. Key link at or above ${pct(erd.thresholds.key_rate)} match; candidates below ${pct(erd.thresholds.min_rate)} are not drawn.`;
}

(async () => {
  try {
    const r = await fetch(ERD); if (!r.ok) throw new Error(`HTTP ${r.status}`);
    erd = await r.json();
  } catch (e) { $('status').textContent = `Could not load erd.json: ${e.message}`; return; }
  $('fit').addEventListener('click', () => { fit = !fit; $('fit').textContent = fit ? 'Actual size' : 'Fit to width'; $('canvas').classList.toggle('fit', fit); });
  $('ref').addEventListener('change', () => { showRef = $('ref').checked; render(); });
  $('expand-all').addEventListener('click', () => {
    const d = diagramFor(erd, parseRoute(location.hash).tab, { reference: showRef });
    if (expanded.size) expanded = new Set(); else expanded = new Set(d.boxes.map((b) => b.key));
    render();
  });
  window.addEventListener('hashchange', () => { expanded = new Set(); const r = parseRoute(location.hash); if (r.expand) expanded.add(r.expand); render(); });
  const r0 = parseRoute(location.hash); if (r0.expand) expanded.add(r0.expand);
  render();
})();
