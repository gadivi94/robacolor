// Mide el copiado de look: para cada look g y par de fotos (A, B), extrae el look de g(A),
// lo aplica a B y compara con g(B). Error = distancia media en Oklab x100 (≈ ΔE).
const fs = require('fs');
const HTML = process.argv[2] || 'web/robacolor.html';
const SET = JSON.parse(process.argv[3] || '{}');           // ajustes de V distintos de los de por defecto
const D = process.env.DATOS || 'datos/';
const raw = fs.readFileSync(HTML, 'utf8'), src = HTML.endsWith('.js') ? raw : raw.match(/\/\* ENGINE:BEGIN \*\/([\s\S]*?)\/\* ENGINE:END \*\//)[1];
const E = new Function(src + '\nreturn {toLab, analyze, compile, process, V, makeLook: typeof makeLook === "function" ? makeLook : null, TUNE: typeof TUNE === "object" ? TUNE : {}, PRIOR: typeof PRIOR === "object" ? PRIOR : []};')();
Object.assign(E.V, SET); if (process.env.TUNE) Object.assign(E.TUNE, JSON.parse(process.env.TUNE)); if (process.env.PRIOR) JSON.parse(process.env.PRIOR).forEach((v, i) => { E.PRIOR[i] = v; });
const meta = fs.readFileSync(D + 'meta.txt', 'utf8').trim().split('\n');
const grades = meta.pop().split(' ');
const imgs = meta.map(l => { const [n, w, h] = l.split(' '); return { n, w: +w, h: +h }; });
const load = f => new Uint8ClampedArray(fs.readFileSync(D + f));
const cache = {};
const get = (g, im) => { const k = g + '_' + im.n; if (!cache[k]) { const px = load(k + '.rgba'), lab = E.toLab(px); cache[k] = { px, lab }; } return cache[k]; };
const dE = (x, y) => { let s = 0; for (let i = 0; i < x.n; i++) s += Math.hypot(x.L[i] - y.L[i], x.A[i] - y.A[i], x.B[i] - y.B[i]); return 100 * s / x.n; };
const only = process.env.ONLY ? process.env.ONLY.split(',') : null;
const byref = {}; const rows = []; let tot = [0, 0, 0], N = 0; const worst = [];
for (const g of grades) {
  if (only && !only.includes(g)) continue;
  let a0 = 0, a1 = 0, n = 0, mx = 0;
  for (const B of imgs) {
    const base = get('base', B), want = get(g, B), tst = E.analyze(base.lab);
    const none = dE(base.lab, want.lab);
    for (const A of imgs) {
      if (A === B) continue;
      const ref = get(g, A);
      const look = E.makeLook ? E.makeLook(ref.lab) : E.analyze(ref.lab);
      const out = new Uint8ClampedArray(base.px.length);
      E.process(E.compile(tst, look), base.lab, out, B.w, B.h, 0, B.w, B.h, { pw: B.w, ph: B.h, blur: null });
      const e = dE(E.toLab(out), want.lab);
      if (process.env.BYREF) { (byref[g + ' ' + A.n] = byref[g + ' ' + A.n] || []).push(e - none); }
      a0 += none; a1 += e; n++; if (e > mx) mx = e; worst.push([e - none, e, none, g, A.n, B.n]);
    }
  }
  rows.push([g, a0 / n, a1 / n, mx]); tot[0] += a0; tot[1] += a1; N += n;
}
console.log('look'.padEnd(13), 'sin tocar'.padStart(10), 'copiado'.padStart(9), 'peor'.padStart(7));
for (const r of rows) console.log(r[0].padEnd(13), r[1].toFixed(2).padStart(10), r[2].toFixed(2).padStart(9), r[3].toFixed(1).padStart(7));
console.log('MEDIA'.padEnd(13), (tot[0] / N).toFixed(2).padStart(10), (tot[1] / N).toFixed(2).padStart(9));
if (process.env.BYREF) for (const k in byref) console.log('  ref', k.padEnd(28), 'error - sin tocar:', (byref[k].reduce((s, v) => s + v, 0) / byref[k].length).toFixed(2));
if (process.env.WORST) { worst.sort((x, y) => y[0] - x[0]); for (const w of worst.slice(0, +process.env.WORST)) console.log('  peor:', w[3], 'ref=' + w[4], 'foto=' + w[5], 'error', w[1].toFixed(1), 'sin tocar', w[2].toFixed(1)); }
