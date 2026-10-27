/* Hub shell: tabs from pages.yaml, theme and scheme picker, per-widget polling.
   The browser only talks to the hub's own /api; the hub talks to the services. */

const $ = (s, r) => (r || document).querySelector(s);
const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
const root = document.documentElement;

/* ---------- helpers handed to every widget's render() ---------- */
const ICON = {
  good: '<svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="4.5"/></svg>',
  warn: '<svg viewBox="0 0 10 10"><path d="M5 0.5 9.5 9 0.5 9z"/></svg>',
  crit: '<svg viewBox="0 0 10 10"><path d="M1 1 9 9M9 1 1 9" stroke="currentColor" stroke-width="2" fill="none"/></svg>'
};
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const fmt = (n, d = 0) => Number(n).toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d });
const pill = (kind, label) => `<span class="pill ${kind}">${ICON[kind]}${esc(label)}</span>`;
const helpers = { esc, fmt, pill };

function ago(ts) {
  if (!ts) return 'never';
  const s = Math.round(Date.now() / 1000 - ts);
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.round(s / 60)}m ago`;
  return `${Math.round(s / 3600)}h ago`;
}
function every(sec) { return sec >= 3600 ? `${sec / 3600}h` : sec >= 60 ? `${sec / 60}m` : `${sec}s`; }

/* ---------- clock ---------- */
function tick() {
  const d = new Date();
  $('#clock').textContent = d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
  $('#date').textContent = d.toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' });
}
tick(); setInterval(tick, 20000);

/* ---------- theme and color schemes ---------- */
function save(key, value) { try { localStorage.setItem(key, value); } catch (x) {} }

$('#theme').addEventListener('click', () => {
  root.dataset.theme = root.dataset.theme === 'light' ? 'dark' : 'light';
  save('hub-theme', root.dataset.theme);
});

// Scheme ids come from themes.css itself, so adding a block there adds a swatch
function schemeIds() {
  const ids = [];
  try {
    for (const rule of $('#themes-css').sheet.cssRules) {
      for (const m of (rule.selectorText || '').matchAll(/data-scheme="([\w-]+)"/g)) {
        if (!ids.includes(m[1])) ids.push(m[1]);
      }
    }
  } catch (x) {}
  return ids.length ? ids : ['slate'];
}
function renderSchemes() {
  const ids = schemeIds();
  if (!ids.includes(root.dataset.scheme)) root.dataset.scheme = ids[0];
  const title = (id) => id.charAt(0).toUpperCase() + id.slice(1);
  $('#schemes').innerHTML = ids.map((id) =>
    `<button class="sw" type="button" data-scheme="${id}" title="${title(id)}" aria-label="${title(id)} color scheme" aria-pressed="${id === root.dataset.scheme}"></button>`
  ).join('') + `<span class="sname">${title(root.dataset.scheme)}</span>`;
}
$('#schemes').addEventListener('click', (e) => {
  const b = e.target.closest('.sw'); if (!b) return;
  root.dataset.scheme = b.dataset.scheme;
  save('hub-scheme', b.dataset.scheme);
  renderSchemes();
});
$('#themes-css').sheet ? renderSchemes() : $('#themes-css').addEventListener('load', renderSchemes);

/* ---------- widget data: one timer per widget, only while a visible page needs it ---------- */
const data = {};          // widget id -> last /api/widgets response
const timers = {};        // widget id -> interval handle
const listeners = {};     // widget id -> callbacks to run after each fetch
let CONFIG = null;

async function poll(wid) {
  try {
    const resp = await fetch(`/api/widgets/${wid}`, { cache: 'no-store' });
    data[wid] = resp.ok ? await resp.json() : { status: 'down', error: `hub returned ${resp.status}`, data: data[wid]?.data };
  } catch (x) {
    data[wid] = { status: 'down', error: 'hub unreachable', data: data[wid]?.data };
  }
  (listeners[wid] || []).forEach((fn) => fn(data[wid]));
}
function watch(wids) {
  Object.keys(timers).forEach((wid) => { if (!wids.includes(wid)) { clearInterval(timers[wid]); delete timers[wid]; } });
  wids.forEach((wid) => {
    if (timers[wid] || !CONFIG.widgets[wid]) return;
    poll(wid);
    timers[wid] = setInterval(() => poll(wid), CONFIG.widgets[wid].interval * 1000);
  });
}
function listen(wid, fn) { (listeners[wid] = listeners[wid] || []).push(fn); }

/* ---------- widget tiles ---------- */
const modules = {};
async function loadWidget(wid) {
  if (!modules[wid]) modules[wid] = import(`/static/widgets/${wid}/widget.js`);
  return modules[wid];
}

async function mountTile(grid, spec) {
  const tile = document.createElement('div');
  tile.className = `tile c${spec.span || 4}`;
  grid.appendChild(tile);
  if (!CONFIG.widgets[spec.id]) {
    tile.innerHTML = `<h2>${esc(spec.id)}</h2><div class="err">No widget named "${esc(spec.id)}" in app/widgets/</div>`;
    return;
  }
  let mod;
  try { mod = await loadWidget(spec.id); } catch (x) {
    tile.innerHTML = `<h2>${esc(spec.id)}</h2><div class="err">static/widgets/${esc(spec.id)}/widget.js failed to load</div>`;
    return;
  }
  const meta = mod.meta || {};
  tile.innerHTML = `<h2>${esc(meta.title || spec.id)}</h2><div class="body"></div><div class="err" hidden></div>` +
    `<div class="src"><span>${esc(meta.source || '')}</span><span class="when"></span></div>`;
  const draw = (r) => {
    tile.classList.toggle('is-down', r.status === 'down');
    tile.classList.toggle('is-stale', r.status === 'stale');
    const err = $('.err', tile);
    err.hidden = !(r.status === 'down' || r.status === 'stale');
    err.textContent = r.status === 'stale' ? `No fresh data since ${ago(r.updated)}` : (r.error || '');
    $('.when', tile).textContent = `${every(CONFIG.widgets[spec.id].interval)} · ${r.updated ? ago(r.updated) : 'waiting'}`;
    if (r.data) mod.render($('.body', tile), r.data, helpers);
  };
  listen(spec.id, draw);
  if (data[spec.id]) draw(data[spec.id]);
}

/* ---------- services launcher ---------- */
const DOT = { up: ['', 'Up'], down: ['crit', 'Down'], pending: ['warn', 'Pending'], maintenance: ['warn', 'Maintenance'] };
function hostOf(url) { return url.replace(/^https?:\/\//, '').replace(/\/.*$/, ''); }

function renderServices(page) {
  const q = $('.search', page).value.trim().toLowerCase();
  const health = data.service_health;
  const monitors = health && health.status !== 'down' ? (health.data?.monitors || {}) : null;
  // No dot at all without a monitor; a hollow ring means a monitor exists but its status is unknown
  const dot = (svc) => {
    if (!svc.kuma) return null;
    if (!monitors || !(svc.kuma in monitors)) return ['none', 'Status unknown'];
    return DOT[monitors[svc.kuma]] || ['none', 'Status unknown'];
  };
  $('.svc-groups', page).innerHTML = CONFIG.services.map((g) => {
    const items = (g.items || []).filter((s) => !q || `${s.name} ${s.desc || ''} ${g.name}`.toLowerCase().includes(q));
    if (!items.length) return '';
    return `<div class="svc-group"><h3>${esc(g.name)}</h3><div class="svc-grid">` + items.map((s) => {
      const state = dot(s);
      const dotHtml = state ? `<span class="dot ${state[0]}" role="img" aria-label="${state[1]}" title="${state[1]}"></span>` : '';
      return `<a class="svc" href="${esc(s.url)}" target="_blank" rel="noopener"><span class="n">${esc(s.name)}${dotHtml}</span>` +
        `<span class="d">${esc(s.desc || '')}</span><span class="h">${esc(hostOf(s.url))}</span></a>`;
    }).join('') + '</div></div>';
  }).join('') || '<p class="note">No service matches that filter.</p>';
  const note = $('.health-note', page);
  note.hidden = !(health && health.status === 'down');
  note.textContent = health?.error ? `Health dots unavailable: ${health.error}` : '';
}

function mountServices(section) {
  section.innerHTML = '<input class="search" type="search" placeholder="Filter services" aria-label="Filter services">' +
    '<p class="note health-note" hidden></p><div class="svc-groups"></div>' +
    '<p class="note">Links open each service\'s own login. Source: <span class="num">services.yaml</span>. Status: Uptime Kuma.</p>';
  $('.search', section).addEventListener('input', () => renderServices(section));
  listen('service_health', () => renderServices(section));
  renderServices(section);
}

/* ---------- pages and routing ---------- */
function widgetsFor(page) {
  return page.type === 'services' ? ['service_health'] : (page.widgets || []).map((w) => (typeof w === 'string' ? w : w.id));
}

function show(id) {
  const page = CONFIG.pages.find((p) => p.id === id) || CONFIG.pages[0];
  $$('.page').forEach((s) => s.classList.toggle('on', s.id === `p-${page.id}`));
  $$('#nav a').forEach((a) => (a.getAttribute('href') === `#${page.id}` ? a.setAttribute('aria-current', 'page') : a.removeAttribute('aria-current')));
  $('#title').textContent = page.title || page.id;
  $('#subtitle').textContent = page.subtitle || '';
  document.title = `${page.title || page.id} · Homelab Hub`;
  watch(widgetsFor(page));
}

async function start() {
  try {
    const resp = await fetch('/api/config', { cache: 'no-store' });
    if (!resp.ok) throw new Error((await resp.json()).detail || `hub returned ${resp.status}`);
    CONFIG = await resp.json();
  } catch (x) {
    const box = $('#config-error');
    box.hidden = false;
    box.innerHTML = `<b>Config error.</b> ${esc(x.message)}`;
    return;
  }

  const total = CONFIG.services.reduce((n, g) => n + (g.items || []).length, 0);
  $('#nav').innerHTML = CONFIG.pages.map((p) =>
    `<a href="#${esc(p.id)}">${esc(p.title || p.id)}${p.type === 'services' ? ` <span class="count">${total}</span>` : ''}</a>`
  ).join('');

  for (const page of CONFIG.pages) {
    const section = document.createElement('section');
    section.className = 'page';
    section.id = `p-${page.id}`;
    $('#pages').appendChild(section);
    if (page.type === 'services') { mountServices(section); continue; }
    const grid = document.createElement('div');
    grid.className = 'grid';
    section.appendChild(grid);
    for (const spec of page.widgets || []) await mountTile(grid, typeof spec === 'string' ? { id: spec } : spec);
  }

  $('#nav').addEventListener('click', (e) => {
    const a = e.target.closest('a'); if (!a) return;
    e.preventDefault();
    const id = a.getAttribute('href').slice(1);
    history.replaceState(null, '', `#${id}`);
    show(id);
  });
  show(location.hash.slice(1));
}
start();
