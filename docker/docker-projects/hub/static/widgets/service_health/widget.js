export const meta = { title: 'Services', source: 'Uptime Kuma' };

export function render(el, d, { pill }) {
  const down = d.not_up || [];
  el.innerHTML = `<div class="big num">${d.up}<small>of ${d.total} up</small></div>` +
    `<div class="delta">${down.length ? down.map((n) => pill('crit', n)).join(' ') : 'Every monitored service is up'}</div>`;
}
