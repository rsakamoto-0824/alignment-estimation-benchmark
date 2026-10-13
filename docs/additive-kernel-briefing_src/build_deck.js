// 追加検証「GPR の質的変数を加法カーネルで扱う」の説明資料（PowerPoint）を pptxgenjs で生成する。
// 使い方: NODE_PATH="$(npm root -g)" node build_deck.js <出力パス>
// 前提: deck_data.json（prepare_data.py の出力）と formulas/（render_formulas.py の出力）が同じフォルダにあり、
//       ADDITIVE_DIR（既定 ../../results_additive）の figures/ に図（python -m src.additive_study の出力）がある。
// 文字・図形・表などの部品は ../deck_common/deck_kit.js（「技術レポートPowerPoint」テンプレートの見た目）。
// タイトルや結論の文は数値から組み立てる。結果が変わったら全スライドを目で確かめる。

const path = require('path');
const fs = require('fs');
const pptxgen = require('pptxgenjs');
const { createDeckKit, SLIDE_W, MARGIN_X, CONTENT_W } = require('../deck_common/deck_kit');

const BASE_DIR = __dirname;
const OUTPUT_PATH = process.argv[2] || path.join(BASE_DIR, 'deck_raw.pptx');
const ADDITIVE_DIR = process.env.ADDITIVE_DIR || path.join(BASE_DIR, '..', '..', 'results_additive');
const FIGURE_DIR = path.join(ADDITIVE_DIR, 'figures');
const D = JSON.parse(fs.readFileSync(path.join(BASE_DIR, 'deck_data.json'), 'utf8'));

const DECK_TITLE = 'GPR の質的変数を加法カーネルで扱う ― 面内推定の追加検証';
const DECK_DATE = '2026年10月14日';

// 質的変数の扱い方の色は、図（src/additive_study.py）と同じ意味にそろえる
const C = {
  night: '1C1B3A',
  indigo: '2F3470',
  indigoLight: '9EA5E0',
  tint: 'EEEFF7',
  ink: '1E1C33',
  muted: '5E6275',
  line: 'B9BDD0',
  grid: 'E4E6EF',
  gray: 'F2F3F7',
  white: 'FFFFFF',
  onDarkSub: 'CDD0EA',
  motifDark: '34336A',
  good: '178F6C',
  bad: 'C2413B',
  none: '898781',
  basis: '2A78D6', basisTint: 'DFEAF8',
  backfit: '86B6EF',
  basis_int: '104281',
  additive: 'EB6834', additiveTint: 'FBE5DA',
  additive_int: 'A33A14',
  mixed: '1BAF7A', mixedTint: 'D8F0E7',
  mixed_int: '0B6E4F',
};
const MODE_LABEL = {
  none: '質的変数なし',
  basis: '基底関数で同時推定',
  backfit: 'Backfitting',
  basis_int: '同時推定＋交互作用',
  additive: '加法カーネル',
  additive_int: '加法カーネル＋交互作用',
  mixed: '混合（Scan 固定・Mark 変量）',
  mixed_int: '混合＋交互作用',
};
const SHORT_LABEL = { ...MODE_LABEL, mixed: '混合', basis: '同時推定', additive: '加法カーネル' };
const MODES = Object.keys(MODE_LABEL).filter((m) => D.modes[m]);
const LEVELS = D.levels;
const lo = LEVELS[0];
const hi = LEVELS[LEVELS.length - 1];
const mid = LEVELS.includes(20) ? 20 : LEVELS[Math.floor(LEVELS.length / 2)];
const N_WAFERS = D.run.n_wafers;

const f1 = (v) => v.toFixed(1);
const f2 = (v) => v.toFixed(2);
const f3 = (v) => v.toFixed(3);
const f0 = (v) => v.toFixed(0);
const pct = (v, d = 0) => (v * 100).toFixed(d);
const signed = (v, d = 1) => `${v > 0 ? '+' : v < 0 ? '−' : '±'}${Math.abs(v).toFixed(d)}`;
const mean = (values) => values.reduce((a, b) => a + b, 0) / values.length;
const rep = (mode, n) => D.modes[mode][String(n)].rep;
const P = (comparison, n) => D.paired_rep[comparison][String(n)];
const PA = (comparison, n) => D.paired_all[comparison][String(n)];
const relTo = (mode, base, n) => 100 * (rep(mode, n) / rep(base, n) - 1);
const levelsWhere = (comparison, sig) => LEVELS.filter((n) => P(comparison, n).sig === sig);
const rangeText = (levels) => (levels.length === 0 ? 'なし' : levels.length === 1 ? `${levels[0]} Shot` : levels.join('・') + ' Shot');
const sigColor = (sig) => (sig === 'better' ? C.good : sig === 'worse' ? C.bad : C.muted);
const hasMixed = Boolean(D.modes.mixed);
const hasInteraction = Boolean(D.interaction);

// 推奨：加法カーネルが同時推定より有意に良い Shot 数（少ない側）は加法カーネル、それ以外は同時推定・混合・加法カーネルのうち平均 RMSE が最小のもの
const CANDIDATES = ['basis', 'additive', 'mixed'].filter((m) => D.modes[m]);
const argminOver = (modes, levels) => modes.reduce((best, m) => (mean(levels.map((n) => rep(m, n))) < mean(levels.map((n) => rep(best, n))) ? m : best), modes[0]);
const LOW_LEVELS = LEVELS.filter((n) => D.paired_rep['additive-basis'][String(n)].sig === 'better' && n < 25);
const HIGH_LEVELS = LEVELS.filter((n) => !LOW_LEVELS.includes(n));
const LOW_REC = 'additive';
const HIGH_REC = argminOver(CANDIDATES, HIGH_LEVELS);
const SINGLE_REC = argminOver(CANDIDATES, LEVELS);  // 1つに決めるなら（全 Shot 数の平均が最小）
const chosen = (n) => (LOW_LEVELS.includes(n) ? LOW_REC : HIGH_REC);
const bestAtLevel = (n, modes) => Math.min(...modes.map((m) => rep(m, n)));
const singleWorst = SINGLE_REC === 'basis' ? 0 : Math.max(0, Math.max(...LEVELS.map((n) => D.paired_rep[`${SINGLE_REC}-basis`][String(n)].rel)));
const switchRegret = Math.max(...LEVELS.map((n) => 100 * (rep(chosen(n), n) / bestAtLevel(n, Object.keys(D.modes)) - 1)));
// 多い Shot 側で、推奨と同時推定の差（20設定の平均、絶対値の最大）
const highGapAll = HIGH_REC === 'basis' ? 0 : Math.max(...HIGH_LEVELS.map((n) => Math.abs(D.paired_all[`${HIGH_REC}-basis`][String(n)].rel)));
const lowText = LOW_LEVELS.length ? `${LOW_LEVELS[LOW_LEVELS.length - 1]} Shot 以下` : '';
const highText = HIGH_LEVELS.length ? `${HIGH_LEVELS[0]} Shot 以上` : '';
const additiveBetter = levelsWhere('additive-basis', 'better');
const additiveWorse = levelsWhere('additive-basis', 'worse');
const mixedBetter = hasMixed ? levelsWhere('mixed-basis', 'better') : [];
const mixedWorse = hasMixed ? levelsWhere('mixed-basis', 'worse') : [];
const mixedSame = hasMixed ? levelsWhere('mixed-basis', 'ns') : [];
const maxWorse = (comparison) => Math.max(...LEVELS.map((n) => P(comparison, n).rel));
// 交互作用のないデータで交互作用を加えたときの損（全 Shot 数の平均、%）
const intCost = (mode) => mean(LEVELS.map((n) => P(`${mode}_int-${mode}`, n).rel));
// 交互作用のあるデータで、Shot 数ごとに最良の扱い方
const INTERACTION_MODES = ['none', 'basis', 'basis_int', 'additive', 'additive_int', 'mixed', 'mixed_int'].filter((m) => hasInteraction && D.interaction[m]);
const interactionBest = hasInteraction
  ? LEVELS.map((n) => INTERACTION_MODES.reduce((best, m) => (D.interaction[m][String(n)] < D.interaction[best][String(n)] ? m : best), INTERACTION_MODES[0]))
  : [];

const pres = new pptxgen();
pres.layout = 'LAYOUT_WIDE';
pres.author = 'Claude Code';
pres.title = DECK_TITLE;
pres.lang = 'ja-JP';

const kit = createDeckKit({ pres, colors: C, deckTitle: DECK_TITLE, formulaDir: path.join(BASE_DIR, 'formulas'), figureDir: FIGURE_DIR });
const {
  toRuns, addText, addBullets, withBreaks, addCard, addLine, addNode, formulaSize, addFormulaCard, addFigure,
  addNumberedCard, addStat, addChip, tableHead, cell, addStyledTable, newContentSlide, chartBase, nextPage, pageCount,
} = kit;

const SECTION = {
  intro: 'INTRODUCTION',
  s1: '01  背景と方法',
  s2: '02  結果',
  s3: '03  考察とまとめ',
};

// =====================================================================
// 1. 表紙
// =====================================================================
{
  const slide = pres.addSlide();
  nextPage();
  slide.background = { color: C.night };
  addText(slide, '技術レポート ｜ アライメント・面内推定（追加検証）', 0.8, 1.3, 7.5, 0.4, { fontSize: 15, bold: true, color: C.indigoLight, charSpacing: 2 });
  addText(slide, withBreaks(['GPR の質的変数を', '加法カーネルで扱う']), 0.8, 1.8, 7.9, 1.75, { fontSize: 36, bold: true, color: C.white, valign: 'middle', lineSpacingMultiple: 1.05 });
  addText(slide, 'Scan 方向・Mark 番号を「変量効果」として縮めて推定すると、少ない Shot の逆効果は消えるか', 0.8, 3.75, 7.6, 0.8, { fontSize: 17, color: C.onDarkSub });
  addText(slide, `前回の評価（模擬 Wafer ${N_WAFERS.toLocaleString()} 枚、制約付き I 最適計画で ${lo}〜${hi} Shot）と同じ条件で、GPR の質的変数の扱いに加法カーネル・混合（Scan は固定効果、Mark は変量効果）と交互作用の項を加えて比べた`,
    0.8, 4.65, 7.3, 1.1, { fontSize: 13.5, color: C.indigoLight });
  addText(slide, DECK_DATE, 0.8, 6.45, 4, 0.35, { fontSize: 13, color: C.onDarkSub });

  const modes = ['none', 'basis', 'additive', 'mixed'].filter((m) => D.modes[m]);
  const groups = [lo, mid];
  const baseY = 5.25;
  const maxH = 3.15;
  const barW = 0.36;
  const gap = 0.07;
  const groupGap = 0.45;
  const x0 = 8.8;
  const vmax = Math.max(...groups.flatMap((n) => modes.map((m) => rep(m, n)))) * 1.12;
  groups.forEach((n, g) => {
    const gx = x0 + g * (modes.length * (barW + gap) + groupGap);
    modes.forEach((mode, i) => {
      const v = rep(mode, n);
      const h = (v / vmax) * maxH;
      const x = gx + i * (barW + gap);
      slide.addShape(pres.shapes.RECTANGLE, { x, y: baseY - h, w: barW, h, fill: { color: C[mode] }, line: { color: C[mode], width: 0.5 } });
      addText(slide, f2(v), x - 0.22, baseY - h - 0.32, barW + 0.44, 0.28, { fontSize: 10, bold: true, color: C.white, align: 'center' });
    });
    addText(slide, `${n} Shot`, gx - 0.1, baseY + 0.06, modes.length * (barW + gap) + 0.1, 0.3, { fontSize: 11, color: C.onDarkSub, align: 'center' });
  });
  addLine(slide, x0 - 0.12, baseY, x0 + 2 * modes.length * (barW + gap) + groupGap + 0.02, baseY, { color: C.onDarkSub, width: 1 });
  modes.forEach((mode, i) => {
    const x = 8.75 + (i % 2) * 2.15;
    const y = 5.75 + Math.floor(i / 2) * 0.3;
    slide.addShape(pres.shapes.RECTANGLE, { x, y: y + 0.06, w: 0.18, h: 0.18, fill: { color: C[mode] }, line: { color: C[mode], width: 0.5 } });
    addText(slide, SHORT_LABEL[mode], x + 0.25, y, 1.9, 0.3, { fontSize: 10.5, color: C.onDarkSub, valign: 'middle' });
  });
  addText(slide, 'RMSE [nm]、GPR matern52・X, Y, 半径', 8.75, 6.45, 4.0, 0.3, { fontSize: 10.5, color: C.onDarkSub });
  slide.addNotes([
    'この資料は、アライメント計測値の面内推定の追加検証です。',
    '前回の評価で、Scan方向とMark番号を質的変数としてGPRに入れると、計測ショットが多いときは誤差が大きく下がる一方、10ショットでは逆に悪くなることが分かりました。',
    'そこで、質的変数をGPRの平均の基底関数としてではなく、カーネルの項、つまり加法カーネルとして入れる方法と、Scan方向だけを基底関数に残す混合の方法を比べました。',
    `右の棒は、${lo}ショットと${mid}ショットでの推定誤差です。数値はすべて模擬データです。`,
  ].join('\n'));
}

// =====================================================================
// 2. 背景と問い
// =====================================================================
{
  const basisVsNoneLo = relTo('basis', 'none', lo);
  const slide = newContentSlide(SECTION.intro, '背景と問い ― 同時推定は加法カーネルではない', [
    '前回の評価の結論と、今回の問いです。',
    `前回は、Scan方向とMark番号を、GPRの平均の基底関数として同時に推定しました。計測ショットが多いと誤差が大きく下がりましたが、${lo}ショットでは質的変数なしより${f1(basisVsNoneLo)}パーセント悪くなりました。`,
    'これに対して、同時推定は加法カーネルなのか、という質問をいただきました。答えは、いいえです。前回の方法では、カーネルは空間の説明変数だけで、質的変数は平均の関数に入っています。',
    '加法カーネルでは、質的変数の効果を平均ゼロの確率変数、つまり変量効果として扱い、計測点が少ないときは効果をゼロの方向へ縮めて推定します。',
    'そこで今回は、加法カーネルで少ないショットの逆効果が消えるか、交互作用の項を加えるとどうなるかを、前回と同じ条件で比べました。検証の途中で、Scan方向の扱いに問題が見つかったので、Scan方向だけを基底関数に残す混合の方法も加えました。',
  ]);
  const prev = [
    ['多い Shot では質的変数が大きく効く', `GPR（matern52・X, Y, 半径）で ${hi} Shot：質的変数なし ${f2(rep('none', hi))} → 同時推定 ${f2(rep('basis', hi))} nm`],
    ['少ない Shot では逆効果', `${lo} Shot：同時推定 ${f2(rep('basis', lo))} nm は質的変数なし ${f2(rep('none', lo))} nm より ${f1(basisVsNoneLo)}% 悪い。Mark ごとのずれを誤って推定し、縞状の誤差が出る`],
    ['Backfitting は同時推定と同じ解', '同じ尤度の座標上昇法なので、収束すれば同時推定と同じになる'],
  ];
  addText(slide, '前回の評価で分かったこと', MARGIN_X, 1.55, 6.2, 0.4, { fontSize: 16, bold: true, color: C.indigo });
  prev.forEach(([title, desc], i) => {
    addNumberedCard(slide, MARGIN_X, 2.05 + i * 1.55, 6.2, 1.38, i + 1, title, desc, { fill: C.gray, color: i === 1 ? C.bad : C.basis, descSize: 12.5 });
  });
  const rx = 7.15;
  const rw = SLIDE_W - MARGIN_X - rx;
  addCard(slide, rx, 1.55, rw, 2.25, { fill: C.night });
  addText(slide, '質問', rx + 0.3, 1.68, rw - 0.6, 0.35, { fontSize: 13, bold: true, color: C.indigoLight });
  addText(slide, 'GPR の同時推定は加法カーネルか？', rx + 0.3, 2.02, rw - 0.6, 0.45, { fontSize: 18, bold: true, color: C.white });
  addText(slide, 'いいえ。カーネルは空間の説明変数だけで、Scan 方向・Mark 番号は平均の基底関数（固定効果）に入っている。効果は縮めずに推定する',
    rx + 0.3, 2.55, rw - 0.6, 1.1, { fontSize: 13, color: C.onDarkSub });
  addCard(slide, rx, 4.0, rw, 2.75, { fill: C.tint });
  addText(slide, '今回の検証', rx + 0.3, 4.12, rw - 0.6, 0.4, { fontSize: 16, bold: true, color: C.indigo });
  addBullets(slide, [
    '加法カーネル（変量効果）で、少ない Shot の逆効果は消えるか',
    hasMixed ? '2水準の Scan 方向だけ固定効果に残す「混合」はどうか' : '多い Shot で同時推定と同じ精度を保てるか',
    'Scan 方向 × Mark 番号の交互作用の項を加えるとどうなるか（交互作用のないデータ・あるデータ）',
  ], rx + 0.3, 4.6, rw - 0.6, 2.1, { fontSize: 13.5, space: 10 });
}

// =====================================================================
// 3. 結論を先に
// =====================================================================
{
  const slide = newContentSlide(SECTION.intro, `結論を先に ― ${lowText}は加法カーネル、${highText}は${SHORT_LABEL[HIGH_REC]}`, [
    '結論を先にお伝えします。',
    `加法カーネルにすると、${lo}ショットの誤差は同時推定より${f1(-P('additive-basis', lo).rel)}パーセント小さくなり、少ないショットの逆効果は消えました。前回このショット数で最良だったTPSより良い結果です。`,
    `ただし、${rangeText(additiveWorse)}では同時推定より有意に悪く、最大で${f1(maxWorse('additive-basis'))}パーセント悪化しました。2水準しかないScan方向の分散タウが0に縮み、Scan方向の差を推定しなくなるためです。`,
    `少ないショットでは、Scan方向の差を固定効果として推定するより、縮めて推定する方が良いことも分かりました。Scan方向だけを固定効果に残した混合は、${lo}ショットで同時推定より${f1(P('mixed-basis', lo).rel)}パーセント悪く、加法カーネルに及びません。一方、${highText}では混合が同時推定と同等以上でした。`,
    `そこで、${lowText}は加法カーネル、${highText}は${MODE_LABEL[HIGH_REC]}と使い分けると、どのショット数でも最良との差は${f1(switchRegret)}パーセント以内です。1つに決めるなら${MODE_LABEL[SINGLE_REC]}で、最大の損は${f1(singleWorst)}パーセントです。`,
    `交互作用の項は、不要なときでも、変量効果にすれば損は約1パーセントにとどまりました。`,
  ]);
  const w = (CONTENT_W - 2 * 0.35) / 3;
  addStat(slide, MARGIN_X, 1.55, w, 2.6, `${signed(P('additive-basis', lo).rel, 0)}%`, `${lo} Shot：対 同時推定`,
    `加法カーネル ${f2(rep('additive', lo))} nm、同時推定 ${f2(rep('basis', lo))} nm、質的変数なし ${f2(rep('none', lo))} nm`, { fill: C.additiveTint, color: C.additive });
  addStat(slide, MARGIN_X + w + 0.35, 1.55, w, 2.6, `${signed(maxWorse('additive-basis'), 1)}%`, '加法カーネルの最大の悪化',
    `${rangeText(additiveWorse)} で同時推定より有意に悪い。2水準の Scan 方向の τ が 0 に縮むため`, { fill: C.gray, color: C.bad });
  addStat(slide, MARGIN_X + 2 * (w + 0.35), 1.55, w, 2.6, `${f1(switchRegret)}%`, '使い分けの最大の差',
    `${lowText}：加法カーネル、${highText}：${MODE_LABEL[HIGH_REC]}`, { fill: C.mixedTint, color: C.mixed });
  addCard(slide, MARGIN_X, 4.35, CONTENT_W, 1.45, { fill: C.night });
  addText(slide, '選び方の更新', MARGIN_X + 0.4, 4.45, 3, 0.4, { fontSize: 14, bold: true, color: C.indigoLight });
  addText(slide, `GPR（matern52）＋ X, Y, 半径。Scan 方向・Mark 番号は ${lowText}：加法カーネル、${highText}：${MODE_LABEL[HIGH_REC]}。1つに決めるなら${MODE_LABEL[SINGLE_REC]}`,
    MARGIN_X + 0.4, 4.85, CONTENT_W - 0.8, 0.9, { fontSize: 15.5, bold: true, color: C.white });
  addCard(slide, MARGIN_X, 5.95, CONTENT_W, 0.9, { fill: C.gray });
  addText(slide, `判定は同じ Wafer どうしの差の 95% 信頼区間（${N_WAFERS.toLocaleString()} 枚）。代表の設定：GPR matern52・X, Y, 半径。交互作用の項は、不要なときの損が変量効果なら約 1%`,
    MARGIN_X + 0.3, 5.95, CONTENT_W - 0.6, 0.9, { fontSize: 13, valign: 'middle' });
}

// =====================================================================
// 4. 3つの扱い方の違い
// =====================================================================
{
  const slide = newContentSlide(SECTION.s1, '同時推定・加法カーネル・混合 ― 効果を「縮めるか」が違う', [
    '3つの方法の違いです。',
    '同時推定では、Scan方向とMark番号の効果コードFを平均の基底関数に入れ、その係数ガンマを計測値から推定します。係数には制約がないので、データが少ないと大きくぶれます。',
    '加法カーネルでは、空間のカーネルに、Scan方向が同じなら1、Mark番号が同じなら1となる項を、それぞれタウの2乗の重みで足します。効果が平均ゼロ、分散タウの2乗の確率変数だと仮定したことと同じで、タウも周辺尤度で推定します。タウを無限大にすると同時推定と一致します。',
    '混合は、2水準しかないScan方向だけを基底関数に残し、4水準のMark番号を加法カーネルにする方法です。',
    '下の式は、単純な場合の縮み方の目安です。点の数が少ないほど、またタウが小さいほど、平均残差をゼロへ縮めます。',
  ], { source: '出典：Rasmussen & Williams (2006) 2.7節、Robinson (1991)。τ → ∞ で同時推定と一致することは tests/test_gpr_additive.py で確認（差 1e-5 未満）' });
  const cards = [
    ['basis', '基底関数で同時推定（前回）', C.basisTint, 'basis_model', ['Scan・Mark とも固定効果', '係数は縮めない', '点が少ないとぶれやすい']],
    ['additive', '加法カーネル', C.additiveTint, 'additive_kernel', ['Scan・Mark とも変量効果', 'τ も周辺尤度で推定し、不要なら 0 へ', '2水準の Scan は τ が不安定']],
    ['mixed', '混合（Scan 固定・Mark 変量）', C.mixedTint, 'mixed_model', ['Scan（2水準）は固定効果', 'Mark（4水準）は変量効果で縮める', '交互作用は τ_{sm} の項を足す']],
  ].filter(([key]) => key !== 'mixed' || hasMixed);
  const gap = 0.3;
  const w = (CONTENT_W - gap * (cards.length - 1)) / cards.length;
  cards.forEach(([key, title, tint, formula, bullets], i) => {
    const x = MARGIN_X + i * (w + gap);
    addCard(slide, x, 1.55, w, 3.45, { fill: C.gray });
    addChip(slide, x + 0.2, 1.66, C[key], title, { fontSize: 14, w: w - 0.4 });
    const size = formulaSize(formula);
    const scale = Math.min(1, (w - 0.5) / size.w);
    addFormulaCard(slide, formula, x + 0.2, 2.1, w - 0.4, 0.75, { fill: tint, scale, alt: title });
    addBullets(slide, bullets, x + 0.3, 3.05, w - 0.6, 1.85, { fontSize: 13, space: 6 });
  });
  addFormulaCard(slide, 'relation', MARGIN_X, 5.2, 7.3, 0.7, { fill: C.tint, scale: 0.92, alt: '加法カーネルと同時推定の関係' });
  addText(slide, '効果に正規分布の事前分布を置いて積分すると加法カーネル。τ → ∞ の極限が同時推定', MARGIN_X, 5.98, 7.3, 0.6, { fontSize: 12, color: C.muted });
  addFormulaCard(slide, 'shrinkage', MARGIN_X + 7.6, 5.2, CONTENT_W - 7.6, 0.9, { fill: C.tint, scale: 0.85, alt: '縮み方の目安' });
  addText(slide, '単純な場合の縮み方：n_{k} は水準 k の点数、r̄_{k} は平均残差、σ² はノイズ', MARGIN_X + 7.6, 6.18, CONTENT_W - 7.6, 0.5, { fontSize: 11.5, color: C.muted });
}

// =====================================================================
// 5. 評価の方法
// =====================================================================
{
  const slide = newContentSlide(SECTION.s1, '評価の方法 ― 前回と同じ Wafer・計画に、扱い方を追加', [
    '評価の方法です。',
    `前回と同じ${N_WAFERS.toLocaleString()}枚の模擬Wafer、同じサンプリング計画、同じ評価指標を使い、GPRの質的変数の扱い方を追加しました。`,
    '追加したのは、同時推定に交互作用の列を足したもの、加法カーネル、加法カーネルに交互作用の項を足したもの、そして混合と、混合に交互作用の項を足したものです。',
    'カーネルは前回と同じ10種類、説明変数はX, Yと、X, Y, 半径の2組です。前回、接線方向の位置Tを加えると悪化したので、今回は除きました。',
    hasInteraction ? `補足として、Scan方向でMarkごとのずれが変わる、つまり交互作用のある模擬データも作り、標準偏差${D.interaction_std}ナノメートルの交互作用を加えて比べました。` : '',
  ].filter(Boolean));
  const rows = [
    ['none', '－', '－', '前回'],
    ['basis', '固定効果（縮めない）', 'なし', '前回'],
    ['backfit', '固定効果（交互に当てはめ）', 'なし', '前回'],
    ['basis_int', '固定効果（縮めない）', '効果コードの積（3列）', '今回'],
    ['additive', '変量効果（τ で縮める）', 'なし', '今回'],
    ['additive_int', '変量効果（τ で縮める）', 'τ_{sm}²·[両方が同じ]', '今回'],
    ['mixed', 'Scan 固定・Mark 変量', 'なし', '今回'],
    ['mixed_int', 'Scan 固定・Mark 変量', 'τ_{sm}²·[両方が同じ]', '今回'],
  ].filter(([key]) => D.modes[key]);
  addStyledTable(slide, [
    tableHead(['扱い方', '質的変数の入れ方', '交互作用', '計算']),
    ...rows.map(([key, how, inter, when]) => [
      { text: MODE_LABEL[key], options: { align: 'left', bold: true, color: C[key] } }, cell(how), { text: toRuns(inter), options: { align: 'center' } },
      cell(when, { bold: when === '今回', color: when === '今回' ? C.additive : C.muted }),
    ]),
  ], MARGIN_X, 1.55, 8.1, [2.9, 2.4, 1.9, 0.9], { fontSize: 11.5, rowH: 0.44 });
  const rx = MARGIN_X + 8.35;
  const rw = SLIDE_W - MARGIN_X - rx;
  addCard(slide, rx, 1.55, rw, 3.2, { fill: C.tint });
  addText(slide, '条件（前回と同じ）', rx + 0.25, 1.68, rw - 0.5, 0.35, { fontSize: 14, bold: true, color: C.indigo });
  addBullets(slide, [
    `模擬 Wafer ${N_WAFERS.toLocaleString()} 枚（同じ乱数）`,
    `制約付き I 最適計画で ${lo}〜${hi} Shot`,
    `カーネル ${D.config.kernels.length} 種 × 説明変数 X, Y ／ X, Y, 半径`,
    '評価：未計測 Shot の全 Mark、真値との RMSE ほか',
    '代表の設定：matern52・X, Y, 半径（前回の推奨）',
  ], rx + 0.25, 2.12, rw - 0.5, 2.55, { fontSize: 12.5, space: 6 });
  if (hasInteraction) {
    addCard(slide, rx, 4.9, rw, 1.55, { fill: C.gray });
    addText(slide, '補足検証：交互作用ありのデータ', rx + 0.25, 4.98, rw - 0.5, 0.35, { fontSize: 13.5, bold: true, color: C.indigo });
    addText(slide, `Scan 差を Mark ごとに変える：δ_{k} = δ + c_{k}、c_{k} ~ N(0, ${D.interaction_std}²) nm。GPR matern52・X, Y, 半径と TPS`,
      rx + 0.25, 5.35, rw - 0.5, 1.05, { fontSize: 12 });
  }
  const hours = D.run.hours + (D.run_mixed ? D.run_mixed.hours : 0);
  const errors = D.run.n_errors + (D.run_mixed ? D.run_mixed.n_errors : 0);
  addText(slide, `計算：追加分は ${N_WAFERS.toLocaleString()} 枚 × ${LEVELS.length} Shot 数 × 20 設定 × 新しい扱い方（合計 約 ${f1(hours)} 時間、失敗 ${errors} 件）`,
    MARGIN_X, 6.62, CONTENT_W, 0.3, { fontSize: 11.5, color: C.muted });
}

// =====================================================================
// 6. 結果：扱い方ごとの RMSE
// =====================================================================
{
  const shown = ['none', 'basis', 'additive', 'mixed', 'basis_int', 'mixed_int'].filter((m) => D.modes[m]);
  const bestAt = (n) => MODES.reduce((best, m) => (rep(m, n) < rep(best, n) ? m : best), MODES[0]);
  const slide = newContentSlide(SECTION.s2, `扱い方ごとの誤差 ― ${lo} Shot は${SHORT_LABEL[bestAt(lo)].replace('カーネル', '')}、${mid} Shot は${SHORT_LABEL[bestAt(mid)]}が最良`, [
    '代表の設定、GPRのmatern52とX, Y, 半径で、質的変数の扱い方ごとの推定誤差を比べました。',
    `${lo}ショットでは、加法カーネルが${f2(rep('additive', lo))}、${hasMixed ? `混合が${f2(rep('mixed', lo))}、` : ''}同時推定が${f2(rep('basis', lo))}、質的変数なしが${f2(rep('none', lo))}ナノメートルでした。前回このショット数で最良だったTPSは${f2(D.tps[String(lo)])}ナノメートルです。`,
    `${mid}ショットでは、加法カーネルが${f2(rep('additive', mid))}と同時推定の${f2(rep('basis', mid))}より大きくなりました。${hasMixed ? `混合は${f2(rep('mixed', mid))}ナノメートルです。` : ''}`,
    `${hi}ショットでは、どの方法もほぼ同じで、同時推定${f2(rep('basis', hi))}、加法カーネル${f2(rep('additive', hi))}${hasMixed ? `、混合${f2(rep('mixed', hi))}` : ''}ナノメートルでした。`,
  ], { source: `GPR matern52・X, Y, 半径。${N_WAFERS.toLocaleString()} 枚の平均 RMSE（X・Y）[nm]` });
  slide.addChart(pres.charts.LINE, shown.map((m) => ({ name: MODE_LABEL[m], labels: LEVELS.map(String), values: LEVELS.map((n) => rep(m, n)) })), {
    x: MARGIN_X, y: 1.45, w: 7.4, h: 5.45, ...chartBase(),
    chartColors: shown.map((m) => C[m]), lineSize: 2.2, lineDataSymbol: 'circle', lineDataSymbolSize: 7,
    showTitle: true, title: '推定誤差 RMSE（X・Y）[nm]',
    showCatAxisTitle: true, catAxisTitle: '計測 Shot 数', valAxisMinVal: 0, valAxisLabelFormatCode: '0.0',
    showLegend: true, legendPos: 'b',
  });
  const rx = MARGIN_X + 7.65;
  const rw = SLIDE_W - MARGIN_X - rx;
  const cols = [lo, 15, mid, 30, hi].filter((n, i, arr) => LEVELS.includes(n) && arr.indexOf(n) === i);
  addStyledTable(slide, [
    tableHead(['扱い方', ...cols.map((n) => `${n}`)]),
    ...MODES.map((m) => [
      { text: SHORT_LABEL[m], options: { align: 'left', bold: true, color: C[m], fontSize: 10 } },
      ...cols.map((n) => {
        const best = Math.min(...MODES.map((mm) => rep(mm, n)));
        return cell(f2(rep(m, n)), { bold: rep(m, n) === best, color: rep(m, n) === best ? C.good : C.ink, fontSize: 10.5 });
      }),
    ]),
    [{ text: '参考：TPS', options: { align: 'left', color: C.muted, fontSize: 10 } }, ...cols.map((n) => cell(f2(D.tps[String(n)]), { color: C.muted, fontSize: 10.5 }))],
  ], rx, 1.55, rw, [rw - 0.6 * cols.length, ...cols.map(() => 0.6)], { fontSize: 10.5, rowH: 0.4 });
  addText(slide, '列：計測 Shot 数。緑の太字：その Shot 数で最良', rx, 6.0, rw, 0.4, { fontSize: 10.5, color: C.muted });
}

// =====================================================================
// 7. 同時推定との比較（統計）
// =====================================================================
{
  const slide = newContentSlide(SECTION.s2, `同時推定との比較 ― 加法カーネルは ${rangeText(additiveWorse)} で劣る`, [
    '同じWaferどうしで、同時推定との誤差の比を見ました。マイナスが良い方向です。',
    `加法カーネルは、同時推定より有意に良いショット数が${rangeText(additiveBetter)}、有意に悪いショット数が${rangeText(additiveWorse)}でした。`,
    hasMixed ? `混合は、有意に良いショット数が${rangeText(mixedBetter)}、差がないショット数が${rangeText(mixedSame)}、有意に悪いショット数が${rangeText(mixedWorse)}でした。` : '',
    hasMixed ? `混合は、${lo}ショットでは質的変数なしと比べても${signed(P('mixed-none', lo).rel)}パーセントでした。少ないショットでScan方向の差を固定効果として推定すると、かえって悪くなります。` : '',
    '右端の列は、カーネル10種類と説明変数2組、合わせて20設定の平均です。',
  ].filter(Boolean), { source: '比：同じ Wafer どうしの RMSE の比の平均（負＝良い）。色：差の 95% 信頼区間で判定（緑＝有意に良い、赤＝有意に悪い、灰＝差なし）' });
  const comps = ['additive-basis', ...(hasMixed ? ['mixed-basis', 'mixed-none'] : ['additive-none'])];
  const titles = { 'additive-basis': '加法 対 同時推定', 'mixed-basis': '混合 対 同時推定', 'mixed-none': '混合 対 質的変数なし', 'additive-none': '加法 対 質的変数なし' };
  const allComp = hasMixed ? 'mixed-basis' : 'additive-basis';
  const rows = LEVELS.map((n) => [
    cell(`${n}`, { bold: true }),
    ...comps.flatMap((c) => [cell(`${signed(P(c, n).rel)}%`, { bold: true, color: sigColor(P(c, n).sig) }), cell(`${pct(P(c, n).win)}%`)]),
    cell(`${signed(PA(allComp, n).rel)}%`, { color: sigColor(PA(allComp, n).sig) }),
  ]);
  const head = ['Shot', ...comps.flatMap((c) => [titles[c], '良くなった Wafer']), `20設定（${titles[allComp]}）`];
  const restW = CONTENT_W - 0.8 - 2.0;
  addStyledTable(slide, [tableHead(head), ...rows],
    MARGIN_X, 1.55, CONTENT_W, [0.8, ...comps.flatMap(() => [(restW / comps.length) * 0.55, (restW / comps.length) * 0.45]), 2.0], { fontSize: 11.5, rowH: 0.5 });
  addCard(slide, MARGIN_X, 5.75, CONTENT_W, 1.1, { fill: C.tint });
  addText(slide, hasMixed
    ? `加法カーネルは ${rangeText(additiveBetter)} で有意に良いが ${rangeText(additiveWorse)} で劣る。混合は ${rangeText(mixedBetter)} で有意に良いが、${rangeText(mixedWorse)} では劣る`
    : `加法カーネルは少ない Shot で効くが、${rangeText(additiveWorse)} で劣る`,
  MARGIN_X + 0.3, 5.75, CONTENT_W - 0.6, 1.1, { fontSize: 14, bold: true, valign: 'middle' });
}

// =====================================================================
// 8. 加法カーネルが劣る理由：Scan の τ が 0 に縮む
// =====================================================================
{
  const sc = (n) => D.scan_collapse[String(n)];
  const tau = (term, axis, n) => D.tau.additive[term][axis][String(n)];
  const slide = newContentSlide(SECTION.s2, 'Scan 方向の τ ― 少ない Shot で 0 に縮み、20 Shot 前後では縮みすぎ', [
    '加法カーネルが中間のショット数で劣る理由を、推定したタウから調べました。',
    `Mark番号のタウは、ショット数によらず真の大きさ、つまり4つのマークのずれの標準偏差の中央値、X成分で${f2(D.truth.mark_X)}ナノメートルの近くに推定されました。`,
    `一方、Scan方向のタウは、${lo}ショットで${pct(sc(lo).rate)}パーセント、${mid}ショットで${pct(sc(mid).rate)}パーセントのWaferで、XかYのどちらかがほぼ0になりました。Scan方向は2水準しかないので、分散を推定する情報がほとんどないためです。`,
    `タウが0になると、Scan方向の差を推定しなくなります。${mid}ショットでは、タウが0になったWaferで同時推定との差が平均${signed(sc(mid).diff_collapsed, 3)}ナノメートル、0にならなかったWaferでは${signed(sc(mid).diff_kept, 3)}ナノメートルでした。`,
    `一方、${lo}ショットでは、タウが0になったWaferでも同時推定より${signed(sc(lo).diff_collapsed, 3)}ナノメートル、0にならなかったWaferでは${signed(sc(lo).diff_kept, 3)}ナノメートルと、どちらも良い結果でした。少ないショットでは、Scan方向の差は面内の傾向と区別しにくく、固定効果として推定するとぶれるためです。`,
    hasMixed ? `実際、Scan方向を固定効果にした混合は、${lo}ショットで同時推定より${signed(P('mixed-basis', lo).rel)}パーセントと、加法カーネルの利点が消えました。` : '',
  ].filter(Boolean), { source: '図：加法カーネル＋交互作用の τ、GPR matern52・X, Y, 半径。点線：模擬データの真の大きさ（Wafer ごとの値の中央値）。表：加法カーネル。τ < 0.05 nm を「ほぼ 0」とした' });
  addFigure(slide, 'figA2_tau.png', MARGIN_X, 1.45, CONTENT_W, 3.6, 'τ の推定値');
  addStyledTable(slide, [
    tableHead(['加法カーネル（X 成分）', ...LEVELS.map((n) => `${n}`), '真の値']),
    [cell('τ Mark 番号（中央値）', { align: 'left', bold: true }), ...LEVELS.map((n) => cell(f2(tau('mark', 'X', n).median))), cell(f2(D.truth.mark_X), { color: C.muted })],
    [cell('τ Scan 方向（中央値）', { align: 'left', bold: true }), ...LEVELS.map((n) => cell(f2(tau('scan', 'X', n).median))), cell(f2(D.truth.scan_X), { color: C.muted })],
    [cell('Scan の τ がほぼ 0 の Wafer（X か Y）', { align: 'left', bold: true }), ...LEVELS.map((n) => cell(`${pct(sc(n).rate)}%`)), cell('－', { color: C.muted })],
    [cell('その Wafer での同時推定との差 [nm]', { align: 'left', bold: true }), ...LEVELS.map((n) => cell(signed(sc(n).diff_collapsed, 3), { color: sc(n).diff_collapsed > 0 ? C.bad : C.good })), cell('－', { color: C.muted })],
  ], MARGIN_X, 5.15, CONTENT_W, [3.6, ...LEVELS.map(() => (CONTENT_W - 4.6) / LEVELS.length), 1.0], { fontSize: 10.5, rowH: 0.33 });
}

// =====================================================================
// 9. 誤差マップ
// =====================================================================
{
  const slide = newContentSlide(SECTION.s2, `誤差マップ ― ${lo} Shot の Mark ごとの縞が変量効果で消える`, [
    '1枚目のWaferで、X方向の推定誤差を地図にしました。上が10ショット、下が40ショットです。',
    '10ショットでは、同時推定でマークごとに正負が入れ替わる縞が出ています。マークごとのずれを誤って推定し、それが全ショットに広がったためです。',
    `加法カーネル${hasMixed ? 'と混合' : ''}では、この縞が消えました。データが少ないので、マークごとのずれを小さく見積もったためです。`,
    '40ショットでは、質的変数を入れた方法はどれもほぼ同じで、質的変数なしより小さくなっています。',
  ], { source: 'Wafer 0 の X 成分、GPR matern52・X, Y, 半径。灰色の点は計測した Mark。誤差 = 推定値 − 真値' });
  addFigure(slide, 'figA3_error_maps.png', MARGIN_X, 1.45, CONTENT_W, 5.45, '誤差マップ');
}

// =====================================================================
// 10. ばらつき
// =====================================================================
{
  const q = (mode, n) => D.quantiles[mode][String(n)];
  const modes = ['none', 'basis', 'additive', 'mixed'].filter((m) => D.quantiles[m]);
  const slide = newContentSlide(SECTION.s2, `Waferごとのばらつき ― ${lo} Shot の悪い側が縮む`, [
    'Waferごとの誤差の分布です。',
    `${lo}ショットでは、同時推定の90パーセント点が${f2(q('basis', lo).q90)}ナノメートルと悪い側に広がっていましたが、加法カーネルでは${f2(q('additive', lo).q90)}${hasMixed ? `、混合では${f2(q('mixed', lo).q90)}` : ''}ナノメートルまで縮みました。`,
    'ショット数が多いと、質的変数を入れた方法の分布はほぼ重なります。',
  ], { source: 'GPR matern52・X, Y, 半径。箱：25〜75% 点、線：中央値、ひげ：箱の長さの 1.5 倍まで（外れ値は表示しない）' });
  addFigure(slide, 'figA5_distribution.png', MARGIN_X, 1.45, CONTENT_W, 3.75, 'ばらつき');
  addStyledTable(slide, [
    tableHead(['90% 点 [nm]', ...LEVELS.map((n) => `${n}`)]),
    ...modes.map((m) => [cell(MODE_LABEL[m], { align: 'left', bold: true, color: C[m] }), ...LEVELS.map((n) => cell(f2(q(m, n).q90)))]),
  ], MARGIN_X, 5.35, CONTENT_W, [3.6, ...LEVELS.map(() => (CONTENT_W - 3.6) / LEVELS.length)], { fontSize: 11, rowH: 0.3 });
}

// =====================================================================
// 11. カーネル
// =====================================================================
{
  const kernels = D.kernels;
  const best = D.ranking[0];
  const nBetter = kernels.filter((k) => k.XYR_additive < k.XYR_basis).length;
  const nBetterMixedLo = hasMixed ? kernels.filter((k) => k.lo_mixed < k.lo_basis).length : 0;
  const slide = newContentSlide(SECTION.s2, `カーネル ― ${nBetter}/${kernels.length} 種で加法カーネルが同時推定を上回る`, [
    'カーネル10種類で、X, Y, 半径の組の全ショット数の平均誤差と、10ショットの誤差を比べました。',
    `全ショット数の平均で、加法カーネルが同時推定より良かったのは、${kernels.length}種類中${nBetter}種類です。少ないショットでの改善が大きいためです。`,
    hasMixed ? `混合は、少ないショットで同時推定より悪くなるため、全ショット数の平均では同時推定に及びませんでした。${lo}ショットで同時推定より良かったのは${nBetterMixedLo}種類です。` : '',
    `全体で最も良かったのは、${best.variant}・${best.feature_set === 'XYR' ? 'X, Y, 半径' : 'X, Y'}の${MODE_LABEL[best.mode]}で、平均${f3(best.rmse)}ナノメートルでした。`,
    '前回と同じく、等方のMatern系と有理2次が良い結果でした。',
  ].filter(Boolean), { source: `値：X, Y, 半径の組の RMSE（X・Y）[nm]。「平均」は全 Shot 数の平均、「${lo}」は ${lo} Shot` });
  const modes = hasMixed ? ['additive', 'mixed'] : ['additive'];
  const heads = ['カーネル', '平均 同時', ...modes.map((m) => `平均 ${SHORT_LABEL[m]}`), `${lo} 同時`, ...modes.map((m) => `${lo} ${SHORT_LABEL[m]}`)];
  const cellsFor = (k) => [
    cell(k.variant, { align: 'left', bold: true }),
    cell(f3(k.XYR_basis)),
    ...modes.map((m) => cell(f3(k[`XYR_${m}`]), { color: k[`XYR_${m}`] < k.XYR_basis ? C.good : C.bad })),
    cell(f2(k.lo_basis)),
    ...modes.map((m) => cell(f2(k[`lo_${m}`]), { color: k[`lo_${m}`] < k.lo_basis ? C.good : C.bad })),
  ];
  const tw = 9.0;
  const colW = (tw - 2.4) / (heads.length - 1);
  addStyledTable(slide, [tableHead(heads), ...kernels.map(cellsFor)], MARGIN_X, 1.55, tw, [2.4, ...heads.slice(1).map(() => colW)], { fontSize: 10.5, rowH: 0.42 });
  addText(slide, '緑：同時推定より小さい、赤：大きい。並びは加法カーネルの平均の小さい順', MARGIN_X, 6.3, tw, 0.4, { fontSize: 10.5, color: C.muted });
  const rx = MARGIN_X + tw + 0.25;
  const rw = SLIDE_W - MARGIN_X - rx;
  addText(slide, '全体の上位（全 Shot 数の平均）', rx, 1.55, rw, 0.35, { fontSize: 12.5, bold: true, color: C.indigo });
  addStyledTable(slide, [
    tableHead(['設定', 'RMSE']),
    ...D.ranking.slice(0, 8).map((rk) => [cell(`${rk.variant}｜${rk.feature_set}｜${SHORT_LABEL[rk.mode]}`, { align: 'left', fontSize: 9, color: C[rk.mode] }), cell(f3(rk.rmse))]),
  ], rx, 1.95, rw, [rw - 0.7, 0.7], { fontSize: 10, rowH: 0.48 });
}

// =====================================================================
// 12. 交互作用の項（交互作用のないデータ）
// =====================================================================
{
  const families = ['basis', 'additive', ...(hasMixed ? ['mixed'] : [])];
  const slide = newContentSlide(SECTION.s2, `交互作用の項 ― 不要なときの損：同時推定 ${signed(intCost('basis'))}%、変量効果 約 ${signed(intCost('additive'))}%`, [
    'Scan方向とMark番号の交互作用の項を加えた場合です。主な模擬データには交互作用がないので、この項は不要です。',
    `同時推定に交互作用の列を加えると、全ショット数の平均で${signed(intCost('basis'))}パーセント悪化しました。係数を縮めないので、不要な3つの係数のぶれがそのまま誤差になります。`,
    `加法カーネルでは${signed(intCost('additive'))}パーセント${hasMixed ? `、混合では${signed(intCost('mixed'))}パーセント` : ''}でした。不要な項のタウが0へ縮むため、損は小さくなります。`,
  ], { source: 'GPR matern52・X, Y, 半径。比：同じ Wafer どうしの RMSE の比の平均（正＝交互作用を加えて悪化）' });
  slide.addChart(pres.charts.BAR, families.map((m) => ({ name: `${SHORT_LABEL[m]}に交互作用を追加`, labels: LEVELS.map(String), values: LEVELS.map((n) => P(`${m}_int-${m}`, n).rel) })), {
    x: MARGIN_X, y: 1.45, w: 7.8, h: 5.4, barDir: 'col', barGrouping: 'clustered', ...chartBase(),
    chartColors: families.map((m) => C[`${m}_int`]), showTitle: true, title: '交互作用を加えたときの RMSE の変化 [%]（交互作用のないデータ）',
    showCatAxisTitle: true, catAxisTitle: '計測 Shot 数', valAxisLabelFormatCode: '0.0',
    showValue: true, dataLabelFormatCode: '0.0', dataLabelFontSize: 8, dataLabelColor: C.ink, dataLabelPosition: 'outEnd',
    showLegend: true, legendPos: 'b',
  });
  const rx = MARGIN_X + 8.1;
  const rw = SLIDE_W - MARGIN_X - rx;
  addCard(slide, rx, 1.55, rw, 5.25, { fill: C.gray });
  addText(slide, '読み取れること', rx + 0.3, 1.7, rw - 0.6, 0.4, { fontSize: 15, bold: true, color: C.indigo });
  addBullets(slide, [
    `同時推定＋交互作用：平均 ${signed(intCost('basis'))}%（${lo} Shot で ${signed(P('basis_int-basis', lo).rel)}%）。縮めない係数が3つ増える`,
    `加法カーネル＋交互作用：平均 ${signed(intCost('additive'))}%`,
    ...(hasMixed ? [`混合＋交互作用：平均 ${signed(intCost('mixed'))}%`] : []),
    '変量効果にすると、不要な項の τ が 0 へ縮むので損が小さい',
  ], rx + 0.3, 2.25, rw - 0.6, 4.4, { fontSize: 13.5, space: 12 });
}

// =====================================================================
// 13. 交互作用のあるデータ（補足検証）
// =====================================================================
if (hasInteraction) {
  const I = (mode, n) => D.interaction[mode][String(n)];
  const IP = (comparison, n) => D.interaction_paired[comparison][String(n)];
  const counts = INTERACTION_MODES.map((m) => [m, interactionBest.filter((b) => b === m).length]).sort((a, b) => b[1] - a[1]);
  const top = counts[0][0];
  const intRec = D.interaction[`${HIGH_REC}_int`] ? `${HIGH_REC}_int` : top;
  const intBase = intRec.replace('_int', '');
  const slide = newContentSlide(SECTION.s2, `交互作用のあるデータ ― ${SHORT_LABEL[top]}が ${counts[0][1]} / ${LEVELS.length} 水準で最良`, [
    `補足として、Scan方向によってマークごとのずれが変わる、交互作用のある模擬データで比べました。交互作用の大きさは標準偏差${D.interaction_std}ナノメートルで、それ以外は同じデータです。`,
    `ショット数ごとの最良は、${LEVELS.map((n, i) => `${n}ショットで${MODE_LABEL[interactionBest[i]]}`).join('、')}でした。`,
    intRec !== intBase ? `${MODE_LABEL[intRec]}は、交互作用の項なしと比べて${lo}ショットで${signed(IP(`${intRec}-${intBase}`, lo).rel)}パーセント、${hi}ショットで${signed(IP(`${intRec}-${intBase}`, hi).rel)}パーセントでした。` : '',
    `同時推定に交互作用の列を加えた場合は、${hi}ショットでは${signed(IP('basis_int-basis', hi).rel)}パーセント、${lo}ショットでは${signed(IP('basis_int-basis', lo).rel)}パーセントでした。`,
  ].filter(Boolean), { source: `交互作用：Scan 差を Mark ごとに δ_k = δ + c_k、c_k ~ N(0, ${D.interaction_std}²) nm。GPR matern52・X, Y, 半径、${N_WAFERS.toLocaleString()} 枚` });
  addFigure(slide, 'figA4_interaction.png', MARGIN_X, 1.45, 7.4, 4.25, '交互作用ありのデータ', { align: 'left' });
  const rx = MARGIN_X + 7.65;
  const rw = SLIDE_W - MARGIN_X - rx;
  const cols = [lo, mid, hi];
  addStyledTable(slide, [
    tableHead(['扱い方', ...cols.map((n) => `${n}`)]),
    ...INTERACTION_MODES.map((m) => [
      { text: SHORT_LABEL[m], options: { align: 'left', bold: true, color: C[m], fontSize: 10 } },
      ...cols.map((n) => {
        const bestV = Math.min(...INTERACTION_MODES.map((mm) => I(mm, n)));
        return cell(f2(I(m, n)), { bold: I(m, n) === bestV, color: I(m, n) === bestV ? C.good : C.ink });
      }),
    ]),
    [{ text: '参考：TPS', options: { align: 'left', color: C.muted, fontSize: 10 } }, ...cols.map((n) => cell(f2(I('tps', n)), { color: C.muted }))],
  ], rx, 1.55, rw, [rw - 2.1, 0.7, 0.7, 0.7], { fontSize: 10.5, rowH: 0.4 });
  addText(slide, '列：計測 Shot 数。値：RMSE（X・Y）[nm]', rx, 5.3, rw, 0.35, { fontSize: 10.5, color: C.muted });
  addCard(slide, MARGIN_X, 5.85, CONTENT_W, 1.0, { fill: C.tint });
  addText(slide, `最良：${LEVELS.map((n, i) => `${n}→${SHORT_LABEL[interactionBest[i]]}`).join('、')}`,
    MARGIN_X + 0.3, 5.85, CONTENT_W - 0.6, 1.0, { fontSize: 13.5, bold: true, valign: 'middle' });
}

// =====================================================================
// 14. 選び方の更新
// =====================================================================
{
  const sec = (mode, n) => D.modes[mode][String(n)].seconds * 1000;
  const levelsText = (levels) => levels.map((n) => `${f2(rep(chosen(n), n))}`).join(' ／ ');
  const slide = newContentSlide(SECTION.s3, `選び方の更新 ― ${lowText}は加法カーネル、${highText}は${SHORT_LABEL[HIGH_REC]}`, [
    '結果をもとに、前回の選び方を更新します。',
    `${lowText}では、Scan方向とMark番号を加法カーネルで入れます。少ないショットではScan方向の差の推定がぶれるので、自動的に縮める加法カーネルが合っています。前回、10ショット前後で勧めたTPSや質的変数なしのGPRより良い結果です。`,
    `${highText}では、${MODE_LABEL[HIGH_REC]}にします。Scan方向の差を固定効果として推定でき、Mark番号は変量効果として扱えます。ただし、カーネル20設定の平均では同時推定との差は${f1(highGapAll)}パーセント以内なので、同時推定のままでも構いません。`,
    `1つに決めたい場合は${MODE_LABEL[SINGLE_REC]}にします。最大の損は${f1(singleWorst)}パーセントです。`,
    'Scan方向でショットの形が変わる可能性があるときは、交互作用の項も加えます。不要なときの損は約1パーセントです。',
    'MATLABのfitrgpでは、BasisFunctionと、KernelFunctionに自作のカーネル関数を渡すと作れるはずですが、今回は確認していません。',
  ]);
  const rows = [
    [lowText, 'GPR matern52', 'X, Y, 半径', MODE_LABEL[LOW_REC], LOW_LEVELS.map((n) => `${n}: ${f2(rep(LOW_REC, n))}`).join('、'), LOW_REC],
    [highText, 'GPR matern52', 'X, Y, 半径', `${MODE_LABEL[HIGH_REC]}（同時推定でも差 ${f1(highGapAll)}% 以内）`, HIGH_LEVELS.filter((n) => [mid, hi].includes(n)).map((n) => `${n}: ${f2(rep(HIGH_REC, n))}`).join('、'), HIGH_REC],
    ['1つに決めるなら', 'GPR matern52', 'X, Y, 半径', MODE_LABEL[SINGLE_REC], `最大の損 ${f1(singleWorst)}%`, SINGLE_REC],
    ['交互作用が疑われる', 'GPR matern52', 'X, Y, 半径', '上の扱い方＋交互作用の項', '不要なときの損 約 1%', null],
    ['前回の推奨（参考）', 'GPR matern52', 'X, Y, 半径', '同時推定（15 Shot 以上）', `${lo}: ${f2(rep('basis', lo))}、${mid}: ${f2(rep('basis', mid))}`, 'basis'],
  ];
  addStyledTable(slide, [
    tableHead(['状況', '手法', '説明変数', '質的変数（Scan・Mark）', 'RMSE [nm]（Shot 数: 値）']),
    ...rows.map(([a, b, c, d, e, mode], i) => [
      cell(a, { align: 'left', bold: true, color: i === rows.length - 1 ? C.muted : C.ink }), cell(b, { align: 'left' }), cell(c),
      cell(d, { bold: i < 2, color: mode && i < 3 ? C[mode] : i === rows.length - 1 ? C.muted : C.ink }), cell(e, { fontSize: 11 }),
    ]),
  ], MARGIN_X, 1.55, CONTENT_W, [2.4, 1.8, 1.4, 3.3, CONTENT_W - 8.9], { fontSize: 12, rowH: 0.48 });
  const modes = ['basis', 'additive', 'mixed', 'backfit'].filter((m) => D.modes[m]);
  addText(slide, '計算時間（1 Wafer、X・Y の合計、20 設定の平均）', MARGIN_X, 4.75, 6.5, 0.35, { fontSize: 13, bold: true, color: C.indigo });
  addStyledTable(slide, [
    tableHead(['扱い方', `${lo} Shot`, `${hi} Shot`]),
    ...modes.map((m) => [cell(MODE_LABEL[m], { align: 'left', bold: true, color: C[m] }), cell(`${f0(sec(m, lo))} ms`), cell(`${f0(sec(m, hi))} ms`)]),
  ], MARGIN_X, 5.12, 6.5, [3.3, 1.6, 1.6], { fontSize: 11, rowH: 0.34 });
  addCard(slide, MARGIN_X + 6.85, 4.75, CONTENT_W - 6.85, 2.05, { fill: C.gray });
  addText(slide, '実装のメモ', MARGIN_X + 7.1, 4.83, 4, 0.35, { fontSize: 13, bold: true, color: C.indigo });
  addBullets(slide, [
    'Python：src/models/gpr.py の additive・mixed（＿int は交互作用つき）',
    'MATLAB fitrgp：BasisFunction と KernelFunction（自作カーネル）で作れるはず（未確認）',
    '計算時間は M1・6並列で実行中の値',
  ], MARGIN_X + 7.1, 5.22, CONTENT_W - 7.35, 1.55, { fontSize: 11.5, space: 5 });
}

// =====================================================================
// 15. 前提と限界
// =====================================================================
{
  const slide = newContentSlide(SECTION.s3, '前提と限界 ― 模擬データの仮定と、次に確かめること', [
    'この追加検証の前提と限界です。',
    '模擬データは前回と同じ仮定で、Mark番号ごとのずれとScan方向の差の大きさは仮定した値です。実データで質的変数の効果がもっと大きい、または小さい場合、縮め方の効き方も変わります。',
    'Scan方向は2水準しかないので、変量効果にするとタウが0に縮みやすいことが分かりました。Wafer単位ではなく、ロット単位でタウを推定する方法も考えられます。',
    '交互作用のあるデータは補足検証として1つの大きさだけを試しました。',
    '次に、実データでの確認、MATLABでの実装、外周の計測誤差を重みとして入れることを確かめる価値があります。',
  ]);
  const limits = [
    '模擬データの成分の大きさ（Mark のずれ、Scan 差、ノイズ）は前回と同じ仮定値',
    'Scan 方向は2水準しかなく、変量効果にすると τ_{s} が 0 に縮みやすい',
    '交互作用のあるデータは大きさ1つ（標準偏差 1 nm）だけで確認',
    '説明変数は X, Y と X, Y, 半径の2組（T は前回の結果から除外）',
  ];
  const nexts = [
    '実データ（複数ロット）で同時推定・混合を比べる',
    'MATLAB fitrgp（BasisFunction＋自作カーネル）で同じ結果になるか確かめる',
    'Wafer をまたいで τ を共有する（ロット単位で推定する）',
    '外周の計測誤差を不均一なノイズ（重み）として入れる',
  ];
  const w = (CONTENT_W - 0.35) / 2;
  addCard(slide, MARGIN_X, 1.6, w, 5.2, { fill: C.gray });
  addText(slide, '前提と限界', MARGIN_X + 0.3, 1.75, w - 0.6, 0.45, { fontSize: 17, bold: true, color: C.bad });
  addBullets(slide, limits, MARGIN_X + 0.3, 2.35, w - 0.6, 4.3, { fontSize: 14, space: 14 });
  const rx = MARGIN_X + w + 0.35;
  addCard(slide, rx, 1.6, w, 5.2, { fill: C.tint });
  addText(slide, '次に確かめること', rx + 0.3, 1.75, w - 0.6, 0.45, { fontSize: 17, bold: true, color: C.indigo });
  nexts.forEach((text, i) => {
    const y = 2.4 + i * 1.0;
    addNode(slide, rx + 0.55, y + 0.3, 0.44, C.indigo, String(i + 1), { fontSize: 13 });
    addText(slide, text, rx + 0.95, y, w - 1.25, 0.66, { fontSize: 14, valign: 'middle' });
  });
}

// =====================================================================
// 16. まとめ
// =====================================================================
{
  const slide = pres.addSlide();
  const pageNo = nextPage();
  slide.background = { color: C.night };
  addText(slide, 'まとめ', 0.8, 0.55, 8, 0.7, { fontSize: 30, bold: true, color: C.white });
  const points = [
    'GPR の同時推定は加法カーネルではない（質的変数は平均の基底関数、効果を縮めない）',
    `加法カーネルにすると ${lo} Shot の誤差が同時推定より ${f0(-P('additive-basis', lo).rel)}% 小さいが、${rangeText(additiveWorse)} では最大 ${f1(maxWorse('additive-basis'))}% 悪い`,
    '原因は 2水準の Scan 方向の τ が 0 に縮むこと（少ない Shot ではそれが良く働く）',
    hasMixed ? `混合（Scan 固定・Mark 変量）は ${highText} で最良に近いが、${lo} Shot では同時推定より ${signed(P('mixed-basis', lo).rel)}%（少ない Shot では Scan を縮めて推定する方が良い）` : '',
    `使い分け（${lowText}：加法、${highText}：${SHORT_LABEL[HIGH_REC]}）なら最良との差は ${f1(switchRegret)}% 以内。交互作用の項の損は変量効果なら約 1%`,
  ].filter(Boolean);
  const colors = [C.basis, C.additive, C.bad, C.mixed, C.mixed_int];
  points.forEach((text, i) => {
    const y = 1.4 + i * 1.05;
    addNode(slide, 1.15, y + 0.45, 0.5, colors[i], String(i + 1), { fontSize: 16 });
    addText(slide, text, 1.65, y, 6.9, 0.95, { fontSize: 14, color: C.white, valign: 'middle' });
  });
  const rx = 8.85;
  const rw = SLIDE_W - 0.8 - rx;
  addCard(slide, rx, 1.5, rw, 5.0, { fill: C.motifDark });
  addText(slide, '推奨する設定（更新）', rx + 0.35, 1.7, rw - 0.7, 0.45, { fontSize: 17, bold: true, color: C.white });
  addBullets(slide, [
    'GPR（matern52）',
    '説明変数：X, Y, 半径',
    `${lowText}：加法カーネル`,
    `${highText}：${MODE_LABEL[HIGH_REC]}`,
    '交互作用が疑われれば τ_{sm} の項も',
  ], rx + 0.35, 2.3, rw - 0.7, 4.0, { fontSize: 14, space: 12, color: C.onDarkSub });
  addText(slide, DECK_TITLE, 0.8, 7.02, 8, 0.3, { fontSize: 9.5, color: C.onDarkSub });
  addText(slide, String(pageNo), SLIDE_W - 1.1, 7.02, 0.5, 0.3, { fontSize: 10, color: C.onDarkSub, align: 'right' });
  slide.addNotes([
    'まとめです。',
    'GPRの同時推定は加法カーネルではなく、質的変数を平均の基底関数として入れ、効果を縮めずに推定する方法でした。',
    `加法カーネルにすると、${lo}ショットの誤差が同時推定より${f0(-P('additive-basis', lo).rel)}パーセント小さくなりましたが、${rangeText(additiveWorse)}では同時推定より悪くなりました。原因は、2水準のScan方向のタウが0に縮むことでした。`,
    hasMixed ? `Scan方向を固定効果、Mark番号を変量効果にした混合は、${highText}では最良に近い一方、${lo}ショットでは同時推定より悪くなりました。少ないショットでは、Scan方向の差を固定効果で推定するより縮めて推定する方が良いためです。` : '',
    '交互作用の項は、変量効果にすれば不要なときの損が小さくなります。',
    `したがって、${lowText}は加法カーネル、${highText}は${MODE_LABEL[HIGH_REC]}と使い分けることをお勧めします。`,
  ].filter(Boolean).join('\n'));
}

// =====================================================================
// 17. 参考文献
// =====================================================================
{
  const slide = newContentSlide(SECTION.s3, '参考文献', [
    '加法カーネルと同時推定の関係、変量効果の縮めの出典です。',
  ]);
  const refs = [
    'C. E. Rasmussen, C. K. I. Williams, Gaussian Processes for Machine Learning, MIT Press (2006).（2.7 節：明示的な基底関数）',
    'MathWorks, "fitrgp — Fit a Gaussian process regression (GPR) model," MATLAB Documentation. https://www.mathworks.com/help/stats/fitrgp.html',
    'G. K. Robinson, "That BLUP is a good thing: the estimation of random effects," Statistical Science 6(1), 15–32 (1991).',
    'S. R. Searle, G. Casella, C. E. McCulloch, Variance Components, Wiley (1992).',
    '前回の評価：「アライメント計測値の面内推定 ― 説明変数と手法の比較」（2026-10-12、alignment-estimation-benchmark）',
  ];
  addBullets(slide, refs.map((r, i) => `[${i + 1}] ${r}`), MARGIN_X, 1.55, CONTENT_W, 3.5, { fontSize: 12.5, space: 8, bullet: false });
  addCard(slide, MARGIN_X, 6.25, CONTENT_W, 0.55, { fill: C.tint });
  addText(slide, '本資料の数値はすべて乱数で生成した模擬 Wafer による（実データ・社内データは使用していない）。計算コードは alignment-estimation-benchmark リポジトリ',
    MARGIN_X + 0.25, 6.25, CONTENT_W - 0.5, 0.55, { fontSize: 12, valign: 'middle' });
}

pres.writeFile({ fileName: OUTPUT_PATH }).then((file) => console.log(`書き出し: ${file}（${pageCount()} 枚）`));
