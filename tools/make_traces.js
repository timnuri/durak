// Records games played by the JavaScript core (the reference) for tools/test_core.gd: node make_traces.js core-dir out.json N
const core = require(require('path').resolve(process.argv[2]));
const N = +(process.argv[4] || 300);
function rng(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; var t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
const cfgs = [{ players: 2 }, { players: 3, transfer: { enabled: true } }, { players: 4, deckSize: 52, throwIn: 'neighbors' },
  { players: 6, deckSize: 52, transfer: { enabled: true, chain: false } }, { players: 2, deckSize: 24, hiddenTrump: { enabled: true } },
  { players: 3, trumpSwap: { enabled: true }, firstTrickLimit: 5, drawOrder: 'clockwise' },
  { players: 2, hiddenTrump: { enabled: true, reveal: 'withLastCard' }, noTrumpThrow: true },
  { players: 4, hiddenTrump: { enabled: true, afterReveal: 'marker' }, throwIn: 'attacker', drawOrder: 'defenderFirst', endgame: { simultaneousOut: 'defenderLoses' } },
  { players: 5, deckSize: 52, handSize: 7, attackLimit: 4, transfer: { enabled: true }, firstAttacker: 'random' }];
const key = a => a.map(x => x.k + (x.c !== undefined ? ':' + x.c : '') + (x.i !== undefined ? '@' + x.i : '')).sort().join(' ');
const out = [];
for (let g = 0; g < N; g++) {
  const cfg = cfgs[g % cfgs.length], r = rng(g + 1);
  const deck = core.cards.shuffle(core.cards.buildDeck(core.rules.validate(cfg).cfg.deckSize), r);
  const first = Math.floor(r() * core.rules.validate(cfg).cfg.players);
  const m = core.newGame(cfg, { deck, first }), s = m.s;
  const steps = [];
  let n = 0;
  while (!s.over && n++ < 3000) {
    const pend = core.pending(s);
    // somebody acts: usually the first pending, sometimes another seat that may throw in
    let seat = pend[0];
    if (r() < 0.25) { const any = []; for (let p = 0; p < s.n; p++) if (core.actions(s, p).length) any.push(p); if (any.length) seat = any[Math.floor(r() * any.length)]; }
    const acts = core.actions(s, seat);
    const allKeys = []; for (let p = 0; p < s.n; p++) allKeys.push(key(core.actions(s, p)));
    let act = r() < 0.2 || pend.indexOf(seat) < 0 ? acts[Math.floor(r() * acts.length)] : core.bots.choose(s, seat, 'normal', r);
    let res = core.apply(s, seat, act);
    if (!res.ok) { act = acts[0]; res = core.apply(s, seat, act); }
    const ev = res.ev;
    steps.push({ seat, act, keys: allKeys, ev: ev.map(e => e.t).join(',') });
  }
  out.push({ cfg, deck, first, steps, final: { hands: s.hands, discard: s.discard.length, result: s.result, trump: s.trump } });
}
require('fs').writeFileSync(process.argv[3], JSON.stringify(out));
console.log('traces', out.length, 'steps', out.reduce((a, t) => a + t.steps.length, 0));
