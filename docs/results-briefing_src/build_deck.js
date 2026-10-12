// アライメント計測値の面内推定 ― 説明変数と手法の比較（PowerPoint）を pptxgenjs で生成する。
// 使い方: NODE_PATH="$(npm root -g)" node build_deck.js <出力パス>
// 前提: deck_data.json（prepare_data.py の出力）と formulas/（render_formulas.py の出力）が同じフォルダにあり、
//       RESULTS_DIR（既定 ../../results）の figures/ に計算結果の図がある。
// 見た目は「技術レポートPowerPoint」テンプレート（濃紺の表紙とまとめ、白地の本文）に合わせる。

const path = require('path');
const fs = require('fs');
const pptxgen = require('pptxgenjs');

const BASE_DIR = __dirname;
const OUTPUT_PATH = process.argv[2] || path.join(BASE_DIR, 'deck_raw.pptx');
const RESULTS_DIR = process.env.RESULTS_DIR || path.join(BASE_DIR, '..', '..', 'results');
const FIGURE_DIR = path.join(RESULTS_DIR, 'figures');
const D = JSON.parse(fs.readFileSync(path.join(BASE_DIR, 'deck_data.json'), 'utf8'));
const formulaSizes = JSON.parse(fs.readFileSync(path.join(BASE_DIR, 'formulas', 'formulas.json'), 'utf8'));

// ---- 定数 ----
const SLIDE_W = 13.333;
const SLIDE_H = 7.5;
const MARGIN_X = 0.6;
const CONTENT_W = SLIDE_W - MARGIN_X * 2;
const FONT = 'BIZ UDGothic';
const DECK_TITLE = 'アライメント計測値の面内推定 ― 説明変数と手法の比較';
const DECK_DATE = '2026年10月12日';

// 手法の系統の色は、結果の図（src/plotting.py）と同じ意味にそろえる
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
  neutral: '8A8FA8',
  white: 'FFFFFF',
  onDarkSub: 'CDD0EA',
  motifDark: '34336A',
  good: '178F6C',
  bad: 'C2413B',
  gpr: '2A78D6', gprTint: 'DFEAF8',
  tps: 'EB6834', tpsTint: 'FBE5DA',
  ok: '1BAF7A', okTint: 'D8F0E7',
  uk: 'EDA100', ukTint: 'FBF0D3',
  gam: 'E87BA4', gamTint: 'FBE3EC',
  xy: '008300', xyTint: 'DDF0DD',
  rt: '4A3AA7', rtTint: 'E6E3F5',
  none: '898781', basis: '2A78D6', backfit: 'EB6834',
};
const FAMILY_ORDER = ['GPR', 'TPS', 'OK', 'UK', 'GAM', 'XY', 'RT'];
const FAMILY_COLOR = { GPR: C.gpr, TPS: C.tps, OK: C.ok, UK: C.uk, GAM: C.gam, XY: C.xy, RT: C.rt };
const FAMILY_TINT = { GPR: C.gprTint, TPS: C.tpsTint, OK: C.okTint, UK: C.ukTint, GAM: C.gamTint, XY: C.xyTint, RT: C.rtTint };
const FAMILY_LABEL = { GPR: 'GPR', TPS: 'TPS', OK: 'Kriging', UK: 'Universal Kriging', GAM: 'GAM', XY: 'XY5次多項式', RT: 'RTモデル' };
const FEATURE_LABEL = { XY: 'X, Y', XYR: 'X, Y, 半径', XYRT: 'X, Y, 半径, T', '-': '－' };
const MODE_LABEL = { none: '質的変数なし', basis: '基底関数で同時推定', backfit: 'Backfitting', factor: '質的変数あり' };
const LEVELS = D.run.levels;
const N_WAFERS = D.run.n_wafers;

const f1 = (v) => v.toFixed(1);
const f2 = (v) => v.toFixed(2);
const f3 = (v) => v.toFixed(3);
const pct = (v, d = 0) => (v * 100).toFixed(d);
const signed = (v, d = 1) => `${v > 0 ? '+' : v < 0 ? '−' : '±'}${Math.abs(v).toFixed(d)}`;
const fixed = (family) => D.best_fixed[family];
const fixedAt = (family, n) => D.best_fixed[family].levels[String(n)];
const bestAt = (n, family) => D.best_by_level[String(n)][family];
const rec = (n) => D.recommendation[String(n)];

const pres = new pptxgen();
pres.layout = 'LAYOUT_WIDE';
pres.author = 'Claude Code';
pres.title = DECK_TITLE;
pres.lang = 'ja-JP';

let pageNumber = 0;

// ---- 文字の補助関数 ----

// "x_{1}" を下付き、"x^{2}" を上付きのランに変換する
function parseRich(text, baseOptions = {}) {
  const runs = [];
  const pattern = /([_^])\{([^}]*)\}/g;
  let last = 0;
  let match;
  while ((match = pattern.exec(text)) !== null) {
    if (match.index > last) runs.push({ text: text.slice(last, match.index), options: { ...baseOptions } });
    const key = match[1] === '_' ? 'subscript' : 'superscript';
    runs.push({ text: match[2], options: { ...baseOptions, [key]: true } });
    last = pattern.lastIndex;
  }
  if (last < text.length) runs.push({ text: text.slice(last), options: { ...baseOptions } });
  return runs;
}

function toRuns(item, baseOptions = {}) {
  if (typeof item === 'string') return parseRich(item, baseOptions);
  if (Array.isArray(item)) return item.flatMap((part) => toRuns(part, baseOptions));
  const { text, breakLine, ...rest } = item;
  const runs = parseRich(text, { ...baseOptions, ...rest });
  if (breakLine && runs.length) runs[runs.length - 1].options.breakLine = true;
  return runs;
}

function addText(slide, content, x, y, w, h, options = {}) {
  const plain = typeof content === 'string' && !/[_^]\{/.test(content);
  slide.addText(plain ? content : toRuns(content), {
    x, y, w, h,
    fontFace: FONT, fontSize: 15, color: C.ink, margin: 0, valign: 'top',
    isTextBox: true, lang: 'ja-JP',
    ...options,
  });
}

function paragraphs(items, { bullet = true, space = 8, indent = 16, color, fontSize, bold } = {}) {
  const runs = [];
  items.forEach((item, index) => {
    const base = {};
    if (color) base.color = color;
    if (fontSize) base.fontSize = fontSize;
    if (bold) base.bold = true;
    const itemRuns = toRuns(item, base);
    itemRuns.forEach((run, j) => {
      if (j === 0) {
        run.options.bullet = bullet ? { indent } : false;
        run.options.paraSpaceAfter = space;
      }
      if (j === itemRuns.length - 1 && index < items.length - 1) run.options.breakLine = true;
    });
    runs.push(...itemRuns);
  });
  return runs;
}

function addBullets(slide, items, x, y, w, h, options = {}) {
  const { bullet, space, indent, ...textOptions } = options;
  slide.addText(paragraphs(items, { bullet, space, indent, color: textOptions.color, fontSize: textOptions.fontSize }), {
    x, y, w, h,
    fontFace: FONT, fontSize: 15, color: C.ink, margin: 0, valign: 'top',
    isTextBox: true, lang: 'ja-JP',
    ...textOptions,
  });
}

function withBreaks(lines) {
  return lines.map((line, j) => ({ text: line, breakLine: j < lines.length - 1 }));
}

// ---- 図形の補助関数 ----

function addCard(slide, x, y, w, h, { fill = C.tint, line, radius = 0.1, shadow = false } = {}) {
  const options = {
    x, y, w, h, rectRadius: radius,
    fill: { color: fill },
    line: line ? { color: line, width: 1 } : { color: fill, width: 0.5 },
  };
  if (shadow) options.shadow = { type: 'outer', color: '000000', opacity: 0.12, blur: 6, offset: 2, angle: 90 };
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, options);
}

// 始点・終点から、正の長さと回転角で線を描く（負の幅・高さを使わない）
function addLine(slide, x1, y1, x2, y2, { color = C.line, width = 1.5, dash, arrow = false } = {}) {
  const dx = x2 - x1;
  const dy = y2 - y1;
  const length = Math.hypot(dx, dy);
  let angle = (Math.atan2(dy, dx) * 180) / Math.PI;
  if (angle < 0) angle += 360;
  const lineOptions = { color, width };
  if (dash) lineOptions.dashType = dash;
  if (arrow) lineOptions.endArrowType = 'triangle';
  slide.addShape(pres.shapes.LINE, {
    x: (x1 + x2) / 2 - length / 2, y: (y1 + y2) / 2, w: length, h: 0,
    rotate: angle, line: lineOptions,
  });
}

function addNode(slide, cx, cy, diameter, fill, label, { color = C.white, fontSize = 16, lineColor } = {}) {
  slide.addShape(pres.shapes.OVAL, {
    x: cx - diameter / 2, y: cy - diameter / 2, w: diameter, h: diameter,
    fill: { color: fill }, line: { color: lineColor || fill, width: lineColor ? 1.25 : 0.5 },
  });
  if (label) {
    addText(slide, label, cx - diameter / 2, cy - diameter / 2, diameter, diameter, {
      align: 'center', valign: 'middle', fontSize, bold: true, color,
    });
  }
}

function formulaSize(key, scale = 1) {
  const size = formulaSizes[key];
  if (!size) throw new Error(`数式画像がありません: ${key}`);
  return { w: size.w * scale, h: size.h * scale };
}

function addFormula(slide, key, x, y, { scale = 1, alt = '' } = {}) {
  const size = formulaSize(key, scale);
  slide.addImage({ path: path.join(BASE_DIR, 'formulas', formulaSizes[key].file), x, y, w: size.w, h: size.h, altText: alt || key });
  return size;
}

function addFormulaCard(slide, key, x, y, w, h, { fill = C.tint, scale = 1, alt = '' } = {}) {
  addCard(slide, x, y, w, h, { fill });
  const size = formulaSize(key, scale);
  addFormula(slide, key, x + (w - size.w) / 2, y + (h - size.h) / 2, { scale, alt });
}

// PNG の縦横比を保ったまま、枠に収まる大きさで貼る
function pngSize(file) {
  const header = fs.readFileSync(file).subarray(16, 24);
  return { w: header.readUInt32BE(0), h: header.readUInt32BE(4) };
}

function addFigure(slide, name, x, y, maxW, maxH, alt, { align = 'center' } = {}) {
  const file = path.join(FIGURE_DIR, name);
  const px = pngSize(file);
  const scale = Math.min(maxW / px.w, maxH / px.h);
  const w = px.w * scale;
  const h = px.h * scale;
  const left = align === 'left' ? x : x + (maxW - w) / 2;
  slide.addImage({ path: file, x: left, y, w, h, altText: alt });
  return { w, h, x: left };
}

function addNumberedCard(slide, x, y, w, h, num, title, desc, { fill = C.gray, color = C.indigo, descSize = 13 } = {}) {
  addCard(slide, x, y, w, h, { fill });
  addNode(slide, x + 0.42, y + 0.42, 0.46, color, String(num), { fontSize: 15 });
  addText(slide, title, x + 0.8, y + 0.17, w - 0.95, 0.5, { fontSize: 15.5, bold: true, valign: 'middle' });
  addText(slide, desc, x + 0.3, y + 0.8, w - 0.55, h - 0.9, { fontSize: descSize });
}

// 大きな数字と短い説明（結論のカードなど）
function addStat(slide, x, y, w, h, value, label, sub, { fill = C.tint, color = C.indigo, valueSize = 40 } = {}) {
  addCard(slide, x, y, w, h, { fill });
  addText(slide, value, x + 0.3, y + 0.2, w - 0.6, 0.9, { fontSize: valueSize, bold: true, color, valign: 'middle' });
  addText(slide, label, x + 0.3, y + 1.15, w - 0.6, 0.45, { fontSize: 14.5, bold: true });
  if (sub) addText(slide, sub, x + 0.3, y + 1.62, w - 0.6, h - 1.72, { fontSize: 12.5, color: C.muted });
}

function addChip(slide, x, y, color, label, { fontSize = 12, w = 2.4 } = {}) {
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: y + 0.06, w: 0.22, h: 0.22, rectRadius: 0.04, fill: { color }, line: { color, width: 0.5 } });
  addText(slide, label, x + 0.32, y, w - 0.32, 0.34, { fontSize, valign: 'middle' });
}

function tableHead(labels, fill = C.indigo) {
  return labels.map((t) => ({ text: t, options: { bold: true, color: C.white, fill: { color: fill }, align: 'center' } }));
}

function cell(text, options = {}) {
  return { text: String(text), options: { align: 'center', ...options } };
}

function addStyledTable(slide, rows, x, y, w, colW, { fontSize = 12.5, rowH = 0.42 } = {}) {
  slide.addTable(rows, {
    x, y, w, colW,
    fontFace: FONT, fontSize, color: C.ink, valign: 'middle', margin: [0.04, 0.1, 0.04, 0.1],
    border: { type: 'solid', color: C.grid, pt: 0.75 }, rowH: Array.isArray(rowH) ? rowH : rows.map(() => rowH),
  });
}

// ---- スライド共通 ----

function newContentSlide(kicker, title, notes, { source } = {}) {
  const slide = pres.addSlide();
  pageNumber += 1;
  slide.background = { color: C.white };
  addText(slide, kicker, MARGIN_X, 0.36, 9, 0.3, { fontSize: 12, bold: true, color: C.indigo, charSpacing: 1 });
  addText(slide, title, MARGIN_X, 0.64, CONTENT_W, 0.72, { fontSize: 26, bold: true, valign: 'middle' });
  addText(slide, source || DECK_TITLE, MARGIN_X, 7.02, 11.4, 0.3, { fontSize: 9.5, color: C.muted });
  addText(slide, String(pageNumber), SLIDE_W - 1.1, 7.02, 0.5, 0.3, { fontSize: 10, color: C.muted, align: 'right' });
  if (notes) slide.addNotes(notes.join('\n'));
  return slide;
}

function chartBase() {
  return {
    catAxisLabelColor: C.muted, valAxisLabelColor: C.muted,
    catAxisLabelFontFace: FONT, valAxisLabelFontFace: FONT,
    catAxisLabelFontSize: 11, valAxisLabelFontSize: 10,
    catAxisLineShow: true, catAxisLineColor: C.line,
    valAxisLineShow: false,
    valGridLine: { color: C.grid, size: 0.75 },
    catGridLine: { style: 'none' },
    dataLabelFontFace: FONT, titleFontFace: FONT, legendFontFace: FONT,
    catAxisTitleFontFace: FONT, valAxisTitleFontFace: FONT,
    catAxisTitleColor: C.muted, valAxisTitleColor: C.muted,
    catAxisTitleFontSize: 11, valAxisTitleFontSize: 11,
    titleColor: C.ink, titleFontSize: 13,
    legendFontSize: 11, legendColor: C.ink,
  };
}

const SECTION = {
  intro: 'INTRODUCTION',
  s1: '01  背景と目的',
  s2: '02  評価の方法',
  s3: '03  結果',
  s4: '04  考察とまとめ',
};

// ---- 結果から言えることを数値で組み立てる補助 ----
const levelLabels = LEVELS.map((n) => `${n}`);
const gprFixed = fixed('GPR');
const gamFixed = fixed('GAM');
const tpsFixed = fixed('TPS');
const familyRmse = (family, n) => fixedAt(family, n).RMSE_XY;
const bestFamilyAt = (n) => FAMILY_ORDER.reduce((best, f) => (bestAt(n, f).RMSE_XY < bestAt(n, best).RMSE_XY ? f : best), 'GPR');
const FE = D.feature_effect;
const feRel = (comparison, family, n) => FE[comparison][family][String(n)].rel;
const feWin = (comparison, family, n) => FE[comparison][family][String(n)].win;
const feSig = (comparison, family, n) => FE[comparison][family][String(n)].sig;
const FX = D.factor_effect;
const fxRel = (comparison, n) => FX[comparison][String(n)].rel;
const BV = D.backfit_vs_basis;
const lo = LEVELS[0];
const hi = LEVELS[LEVELS.length - 1];
const mid = LEVELS.includes(20) ? 20 : LEVELS[Math.floor(LEVELS.length / 2)];
// 質的変数を入れた方が良くなる最小の Shot 数（全カーネル平均の basis − none が有意に負）
const factorHelpsFrom = LEVELS.find((n) => FX['basis-none'][String(n)].sig === 'better');
const famRel = (family, n) => 100 * (familyRmse(family, n) / familyRmse('GPR', n) - 1);
const gprMode = (n, mode) => D.gpr_best_by_mode[String(n)][mode];
const factorHurtsAtLo = FX['basis-none'][String(lo)].sig === 'worse';
const sigText = { better: '有意に改善', worse: '有意に悪化', ns: '差なし' };

// =====================================================================
// 1. 表紙
// =====================================================================
{
  const slide = pres.addSlide();
  pageNumber += 1;
  slide.background = { color: C.night };
  addText(slide, '技術レポート ｜ アライメント・面内推定', 0.8, 1.3, 7, 0.4, { fontSize: 15, bold: true, color: C.indigoLight, charSpacing: 2 });
  addText(slide, withBreaks(['アライメント計測値の面内推定', '説明変数と手法の比較']), 0.8, 1.8, 7.9, 1.75, { fontSize: 34, bold: true, color: C.white, valign: 'middle', lineSpacingMultiple: 1.05 });
  addText(slide, `GPR・TPS・Kriging・GAM・XY5・RT の${D.run.n_methods}設定を、模擬Wafer ${N_WAFERS.toLocaleString()}枚で比較`, 0.8, 3.75, 7.8, 0.5, { fontSize: 18, color: C.onDarkSub });
  addText(slide, `制約付きI最適計画で選んだ${lo}〜${hi} Shotを学習データとし、未計測Shotの全Markを推定。説明変数（X, Y／半径／T）と、Scan方向・Mark番号を質的変数として扱う効果（Backfittingを含む）を、決定係数・自由度調整済み決定係数・RMSE・MAEで評価した`,
    0.8, 4.45, 7.2, 1.3, { fontSize: 13.5, color: C.indigoLight });
  addText(slide, DECK_DATE, 0.8, 6.45, 4, 0.35, { fontSize: 13, color: C.onDarkSub });

  // 右：20 Shot での系統ごとの最良 RMSE（表紙のモチーフ）
  const baseY = 5.3;
  const maxH = 3.2;
  const barW = 0.42;
  const gap = 0.16;
  const x0 = 8.75;
  const values = FAMILY_ORDER.map((f) => familyRmse(f, mid));
  const vmax = Math.max(...values) * 1.1;
  FAMILY_ORDER.forEach((family, i) => {
    const v = values[i];
    const h = (v / vmax) * maxH;
    const x = x0 + i * (barW + gap);
    slide.addShape(pres.shapes.RECTANGLE, { x, y: baseY - h, w: barW, h, fill: { color: FAMILY_COLOR[family] }, line: { color: FAMILY_COLOR[family], width: 0.5 } });
    addText(slide, f1(v), x - 0.2, baseY - h - 0.34, barW + 0.4, 0.3, { fontSize: 11.5, bold: true, color: C.white, align: 'center' });
    addText(slide, FAMILY_LABEL[family].replace('Universal Kriging', 'UK').replace('XY5次多項式', 'XY5').replace('RTモデル', 'RT'), x - 0.2, baseY + 0.06, barW + 0.4, 0.3, { fontSize: 10, color: C.onDarkSub, align: 'center' });
  });
  addLine(slide, x0 - 0.12, baseY, x0 + 7 * (barW + gap) - gap + 0.12, baseY, { color: C.onDarkSub, width: 1 });
  addText(slide, `${mid} Shot計測時の推定誤差 RMSE [nm]（系統ごとの最良の設定、${N_WAFERS.toLocaleString()}枚の平均）`, 8.4, 5.75, 4.4, 0.6, { fontSize: 11.5, color: C.onDarkSub, align: 'center' });
  slide.addNotes([
    'この資料では、アライメント計測値の面内推定について、どの手法とどの説明変数を選べばよいかを評価した結果を説明します。',
    `乱数で作った${N_WAFERS.toLocaleString()}枚の模擬Waferに対し、制約付きI最適計画で${lo}から${hi}ショットを選んで学習データとし、残りのショットの全マークを推定しました。`,
    `比べたのはGPR、TPS、Kriging、Universal Kriging、GAM、XY5次多項式、RTモデルの7系統で、カーネルやバリオグラム、説明変数の組み合わせを含めて${D.run.n_methods}通りです。`,
    `右の棒は${mid}ショット計測時の、系統ごとの最良の推定誤差です。数値はすべて模擬データで、実データではありません。`,
  ].join('\n'));
}

// =====================================================================
// 2. この資料で分かること
// =====================================================================
{
  const slide = newContentSlide(SECTION.intro, 'この資料で分かること', [
    '全体は4つのパートです。',
    'まず、なぜ未計測ショットの推定が必要か、アライメント計測値にどんな特徴があるかを確認します。',
    '次に、模擬データの作り方、サンプリング、比べた手法と説明変数、評価指標を説明します。',
    'そのあと結果として、手法と説明変数の比較、質的変数とBackfittingの効果、カーネルやバリオグラムの違い、4つの指標の違い、外周での精度を見ます。',
    '最後に、手法と説明変数の選び方と、この評価の前提と限界をまとめます。',
  ]);
  addCard(slide, MARGIN_X, 1.55, CONTENT_W, 0.7, { fill: C.tint });
  addNode(slide, MARGIN_X + 0.45, 1.9, 0.42, C.indigo, '✓', { fontSize: 14 });
  addText(slide, 'ゴール：計測Shot数に応じて、面内推定の手法・説明変数・質的変数の扱いを数値の根拠で選べるようになる',
    MARGIN_X + 0.85, 1.55, CONTENT_W - 1.1, 0.7, { fontSize: 15, bold: true, valign: 'middle' });
  const parts = [
    ['背景と目的', '未計測Shotの推定と、計測値の3つの特徴（Shot形状・Scan方向・外周のノイズ）', 'p.4–5', C.gpr],
    ['評価の方法', '模擬データ、制約付きI最適計画、7系統123設定の手法、説明変数、4指標', 'p.6–12', C.tps],
    ['結果', '手法×説明変数の比較、質的変数とBackfitting、カーネル、指標、外周', 'p.13–26', C.ok],
    ['考察とまとめ', '選び方のガイド、前提と限界、まとめ', 'p.27–30', C.rt],
  ];
  const w = (CONTENT_W - 3 * 0.3) / 4;
  parts.forEach(([title, desc, pages, color], i) => {
    const x = MARGIN_X + i * (w + 0.3);
    const y = 2.6;
    addCard(slide, x, y, w, 3.6, { fill: C.gray });
    addNode(slide, x + 0.55, y + 0.6, 0.66, color, String(i + 1).padStart(2, '0'), { fontSize: 18 });
    addText(slide, title, x + 0.25, y + 1.15, w - 0.45, 0.6, { fontSize: 17, bold: true });
    addText(slide, desc, x + 0.25, y + 1.8, w - 0.45, 1.3, { fontSize: 13, color: C.muted });
    addText(slide, pages, x + 0.25, y + 3.1, w - 0.45, 0.3, { fontSize: 11, color: C.muted });
  });
  addText(slide, '想定する読者：アライメント・重ね合わせ補正の担当者。数式は「何を表すか」が分かる粒度で示します。',
    MARGIN_X, 6.45, CONTENT_W, 0.4, { fontSize: 13, color: C.muted });
}

// =====================================================================
// 3. 結論を先に
// =====================================================================
{
  const g = (n) => familyRmse('GPR', n);
  const bestLo = bestFamilyAt(lo);
  const slide = newContentSlide(SECTION.intro, `結論を先に ― ${factorHelpsFrom} Shot 以上は GPR＋質的変数＋半径。T は加えない`, [
    '結論を先にお伝えします。',
    `全体で最も良かったのは、${gprFixed.label}でした。推定誤差のRMSEは、${mid}ショットで${f2(g(mid))}、${hi}ショットで${f2(g(hi))}ナノメートルです。`,
    `Scan方向とMark番号を質的変数として入れると、GPRの誤差は${hi}ショットで平均${f0(-fxRel('basis-none', hi))}パーセント小さくなりました。ただし${lo}ショットでは${factorHurtsAtLo ? `逆に${f1(fxRel('basis-none', lo))}パーセント悪くなりました` : '効果がほとんどありませんでした'}。点が少ないと、質的変数の効果を面内の傾向と区別できないためです。${lo}ショットでは、質的変数なしのGPRとTPSが同程度に良い結果でした。`,
    `Backfittingで追い込んでも、基底関数として同時に推定した場合とほぼ同じ結果でした。差が0.01ナノメートル未満の場合が${pct(BV.share_within_001)}パーセントです。両者は同じ尤度を最大化しているためです。`,
    `説明変数は、半径を足すとGPRで数パーセント良くなり、接線方向の位置Tを足すと悪くなりました。ARDカーネルでは、Tが多くの場合に無視されました。`,
    'Kriging、XY5次、RTモデルは、GPRより大きく劣りました。',
  ]);
  const w = (CONTENT_W - 2 * 0.35) / 3;
  addStat(slide, MARGIN_X, 1.55, w, 2.7, `${f2(g(mid))} nm`, `最良：${FAMILY_LABEL.GPR}（${mid} Shot）`,
    `${gprFixed.variant}・${FEATURE_LABEL[gprFixed.feature_set]}・${MODE_LABEL[gprFixed.factor_mode]}。${lo} Shot ${f2(g(lo))} → ${hi} Shot ${f2(g(hi))} nm`, { fill: C.gprTint, color: C.gpr });
  addStat(slide, MARGIN_X + w + 0.35, 1.55, w, 2.7, `${signed(fxRel('basis-none', hi), 0)}%`, `質的変数の効果（${hi} Shot）`,
    `Scan方向・Mark番号の効果コードを基底関数に追加。${factorHelpsFrom} Shot 以上で有意に改善、${lo} Shot では ${signed(fxRel('basis-none', lo))}%`, { fill: C.tint, color: C.good });
  addStat(slide, MARGIN_X + 2 * (w + 0.35), 1.55, w, 2.7, `${pct(BV.share_within_001)}%`, 'Backfitting ≒ 同時推定',
    `RMSE の差が 0.01 nm 未満の割合。同じ尤度の座標上昇法なので同じ解に収束する（反復は平均 ${f1(BV.iter_mean)} 回）`, { fill: C.gray, color: C.indigo });
  addCard(slide, MARGIN_X, 4.45, CONTENT_W, 1.45, { fill: C.night });
  addText(slide, '選び方', MARGIN_X + 0.4, 4.55, 2, 0.4, { fontSize: 14, bold: true, color: C.indigoLight });
  addText(slide, `${factorHelpsFrom} Shot 以上：GPR（${gprFixed.variant}）＋ X, Y, 半径 ＋ Scan 方向・Mark 番号を基底関数で同時推定。${lo} Shot 前後：質的変数を入れない GPR か TPS（X, Y, 半径）。T（方位角）は加えない。Backfitting は同時推定と同じ結果`,
    MARGIN_X + 0.4, 4.95, CONTENT_W - 0.8, 0.9, { fontSize: 15, bold: true, color: C.white });
  addCard(slide, MARGIN_X, 6.05, CONTENT_W, 0.8, { fill: C.gray });
  addText(slide, `劣った手法：Kriging（バリオグラムの当てはめが粗く、ナゲットを過大に推定）、XY5次・RT（66項のZernikeとMarkのOffsetを表せない）。GAM（質的変数あり）は${hi} Shot で GPR に次ぐ`,
    MARGIN_X + 0.3, 6.05, CONTENT_W - 0.6, 0.8, { fontSize: 13, valign: 'middle' });
}

// =====================================================================
// 4. 背景
// =====================================================================
{
  const slide = newContentSlide(SECTION.s1, '背景 ― 少ないShotの計測値から、Wafer全体の値を推定したい', [
    'アライメント計測では、計測時間の制約から、全ショットではなく一部のショットだけを計測します。',
    '補正や監視には計測していないショットの値も必要になるため、計測した値からWafer全体の値を推定します。これを面内推定と呼びます。',
    'アライメント計測値には、推定を難しくする特徴が3つあります。',
    '1つ目は、ショットの形のばらつきによる、マーク番号ごとの共通のずれです。2つ目は、スキャン方向による差です。3つ目は、Waferの外周ほど計測誤差が大きいことです。',
    'これらを、説明変数や質的変数としてどう扱うかが、手法選びのポイントになります。',
  ]);
  // 左：流れ
  const steps = [
    ['一部の Shot を計測', '制約付き I 最適計画で選んだ 10〜40 Shot の全 Mark を計測する'],
    ['面内の傾向を推定', '計測値から、Wafer 全体で連続な関数（＋質的変数の効果）を当てはめる'],
    ['未計測 Shot を推定', '当てはめた関数で、計測していない Shot の全 Mark の値を求める'],
  ];
  steps.forEach(([title, desc], i) => {
    const y = 1.6 + i * 1.62;
    addNumberedCard(slide, MARGIN_X, y, 5.6, 1.38, i + 1, title, desc, { fill: C.gray, color: C.gpr, descSize: 13.5 });
    if (i < steps.length - 1) addLine(slide, MARGIN_X + 0.42, y + 1.38, MARGIN_X + 0.42, y + 1.62, { color: C.line, width: 1.5, arrow: true });
  });
  const rx = 6.6;
  const rw = SLIDE_W - MARGIN_X - rx;
  addText(slide, 'アライメント計測値の3つの特徴', rx, 1.6, rw, 0.4, { fontSize: 16, bold: true, color: C.indigo });
  const traits = [
    ['Shot 形状のばらつき', 'Mark 番号ごとに、全 Shot 共通のずれ（Offset）がのる。Wafer ごとに大きさが変わる', C.gam],
    ['Scan 方向の差', 'Scan 方向（上向き・下向き）で値に差がある。Shot の列ごとに方向が入れ替わる', C.uk],
    ['外周ほど大きい計測誤差', 'Wafer の外周ほど計測ノイズが大きい。外周の推定は外挿にもなる', C.tps],
  ];
  traits.forEach(([title, desc, color], i) => {
    const y = 2.15 + i * 1.5;
    addCard(slide, rx, y, rw, 1.3, { fill: C.gray });
    addNode(slide, rx + 0.45, y + 0.65, 0.5, color, String(i + 1), { fontSize: 15 });
    addText(slide, title, rx + 0.9, y + 0.13, rw - 1.1, 0.42, { fontSize: 15.5, bold: true, valign: 'middle' });
    addText(slide, desc, rx + 0.9, y + 0.55, rw - 1.1, 0.7, { fontSize: 13 });
  });
}

// =====================================================================
// 5. 評価の問いと流れ
// =====================================================================
{
  const slide = newContentSlide(SECTION.s1, '評価の問い ― 手法・説明変数・質的変数の扱いをどう選ぶか', [
    '今回の評価で答えたい問いは3つです。',
    '1つ目は、どの推定手法が良いか。GPR、TPS、Kriging、Universal Kriging、GAM、XY5次多項式、RTモデルを比べます。',
    '2つ目は、どの説明変数を使うか。X, Yだけ、半径を加える、さらに接線方向の位置Tを加える、の3通りです。',
    '3つ目は、Scan方向とMark番号の質的変数をどう扱うか。GPRでは、使わない、基底関数として同時に推定する、Backfittingで追い込む、の3通りを比べます。',
    `評価は${N_WAFERS.toLocaleString()}枚の模擬Waferで、7通りのショット数ごとに、未計測ショットの推定精度を4つの指標で測りました。`,
  ]);
  const questions = [
    ['どの手法か', 'GPR（10カーネル）、TPS、Kriging・Universal Kriging（4バリオグラム）、GAM、XY5次、RT', C.gpr],
    ['どの説明変数か', 'X, Y ／ X, Y, 半径 ／ X, Y, 半径, T（T = 方位角 θ）', C.tps],
    ['質的変数の扱い', 'Scan 方向・Mark 番号を GPR では「なし／同時推定／Backfitting」、GAM では説明変数に追加', C.gam],
  ];
  const w = (CONTENT_W - 2 * 0.3) / 3;
  questions.forEach(([title, desc, color], i) => {
    const x = MARGIN_X + i * (w + 0.3);
    addCard(slide, x, 1.6, w, 1.95, { fill: C.gray });
    addNode(slide, x + 0.5, 2.05, 0.56, color, `Q${i + 1}`, { fontSize: 14 });
    addText(slide, title, x + 0.95, 1.8, w - 1.1, 0.5, { fontSize: 17, bold: true, valign: 'middle' });
    addText(slide, desc, x + 0.3, 2.5, w - 0.55, 1.0, { fontSize: 13 });
  });
  // 流れ
  const flow = [
    ['模擬 Wafer を作る', `${N_WAFERS.toLocaleString()} 枚。Zernike＋Mark Offset＋Scan差＋ノイズ`],
    ['Shot を選ぶ', `制約付き I 最適計画、${lo}〜${hi} Shot（5刻み）`],
    ['推定する', `${D.run.n_methods} 設定の手法で未計測 Shot の全 Mark`],
    ['評価する', 'ノイズなしの真値と比べ R²・調整済み R²・RMSE・MAE'],
  ];
  const fw = (CONTENT_W - 3 * 0.45) / 4;
  flow.forEach(([title, desc], i) => {
    const x = MARGIN_X + i * (fw + 0.45);
    addCard(slide, x, 4.0, fw, 2.3, { fill: C.tint });
    addText(slide, `STEP ${i + 1}`, x + 0.25, 4.15, fw - 0.5, 0.3, { fontSize: 11, bold: true, color: C.indigo, charSpacing: 1 });
    addText(slide, title, x + 0.25, 4.5, fw - 0.5, 0.5, { fontSize: 16, bold: true });
    addText(slide, desc, x + 0.25, 5.1, fw - 0.5, 1.1, { fontSize: 13, color: C.muted });
    if (i < flow.length - 1) addLine(slide, x + fw + 0.07, 5.15, x + fw + 0.38, 5.15, { color: C.indigo, width: 2, arrow: true });
  });
  addText(slide, '評価対象は「未計測 Shot の全 Mark」。計測ノイズを含まない真値（面内傾向＋Mark Offset＋Scan差）と比べる',
    MARGIN_X, 6.5, CONTENT_W, 0.35, { fontSize: 12.5, color: C.muted });
}

// =====================================================================
// 6. 模擬データ
// =====================================================================
{
  const st = D.data;
  const slide = newContentSlide(SECTION.s2, '模擬データ ― 4つの成分を足してWaferごとの計測値を作る', [
    '模擬データは、4つの成分の和として作りました。',
    `1つ目は面内傾向で、動径次数10次までのZernike多項式66項から、10から30項をランダムに選びます。係数は高次ほど小さくしました。Wafer全体のRMSは平均${f1(st.trend_rms_mean)}ナノメートルです。`,
    `2つ目はMark番号ごとのOffsetで、全ショット共通のずれです。基準のパターンにWaferごとの乱数を足し、RMSは平均${f2(st.mark_rms_mean)}ナノメートルです。`,
    `3つ目はScan方向の差で、Waferごとの差の半分をそれぞれの方向に足します。RMSは平均${f2(st.scan_rms_mean)}ナノメートルです。`,
    '4つ目は計測ノイズで、一様分布です。幅は中心でプラスマイナス1ナノメートル、最外周のマークでプラスマイナス3ナノメートルになるよう、半径の3乗で広げました。',
    '図は1枚目のWaferのX方向の値です。',
  ], { source: '図：Wafer 0 の X 成分。各点が Mark（99 Shot × 4 Mark）。右端はノイズの幅（線）と実際のノイズ（点）' });
  addFormulaCard(slide, 'data_model', MARGIN_X, 1.5, 5.6, 0.75, { fill: C.tint, scale: 0.9, alt: 'm = f + o + s δ/2 + ε' });
  addText(slide, 'k(i)：Mark 番号、s(i) = ±1：Scan 方向、δ：Wafer ごとの Scan 差', MARGIN_X + 5.85, 1.62, CONTENT_W - 5.85, 0.55, { fontSize: 12.5, color: C.muted, valign: 'middle' });
  addFigure(slide, 'fig02_data_components.png', MARGIN_X, 2.45, CONTENT_W, 2.75, '模擬データの4成分');
  const comps = [
    ['面内傾向', `Zernike 66項から10〜30項。RMS 平均 ${f1(st.trend_rms_mean)} nm（10〜90%点 ${f1(st.trend_rms_p10)}〜${f1(st.trend_rms_p90)}）`, C.gpr],
    ['Mark Offset', `Mark 番号ごと・全 Shot 共通。RMS 平均 ${f2(st.mark_rms_mean)} nm`, C.gam],
    ['Scan 方向の差', `方向1に +δ/2、方向2に −δ/2。RMS 平均 ${f2(st.scan_rms_mean)} nm`, C.uk],
    ['計測ノイズ', `一様分布。中心 ±1 → 最外周 ±3 nm。RMS 平均 ${f2(st.noise_rms_mean)} nm`, C.tps],
  ];
  const w = (CONTENT_W - 3 * 0.25) / 4;
  comps.forEach(([title, desc, color], i) => {
    const x = MARGIN_X + i * (w + 0.25);
    addCard(slide, x, 5.4, w, 1.45, { fill: C.gray });
    addChip(slide, x + 0.2, 5.5, color, title, { fontSize: 13.5, w: w - 0.3 });
    addText(slide, desc, x + 0.25, 5.95, w - 0.45, 0.85, { fontSize: 12 });
  });
}

// =====================================================================
// 7. 設定値
// =====================================================================
{
  const cfg = D.config;
  const st = D.data;
  const slide = newContentSlide(SECTION.s2, '設定値 ― 確認して決めた値と、仮定した値', [
    '模擬データとWaferの設定値です。',
    `ショットは22×26ミリ、マークはショット中心からプラスマイナス10、プラスマイナス12ミリの4点で、全マークが半径147ミリより内側にある${st.n_shots}ショット、${st.n_marks}マークを使いました。スキャン方向は列ごとに交互です。`,
    `Zernikeの係数の標準偏差は、動径次数nに対して${cfg.coef_std_order0_nm}かける${cfg.coef_std_decay}のn乗ナノメートルとしました。高次ほど小さくするという方針は確認済みですが、具体的な値は仮定です。`,
    'Mark OffsetとScan方向の差の大きさ、ノイズの幅を半径の何乗で広げるかも仮定です。',
    '表の右の列に、確認した項目と仮定した項目を分けて示しました。',
  ]);
  const rows = [
    ['Wafer・Shot', `300 mm、端の除外 3 mm。Shot 22×26 mm、Mark (±10, ±12) mm。${st.n_shots} Shot・${st.n_marks} Mark、Scan 方向は列ごとに交互`, '仮定'],
    ['面内傾向', 'Zernike（RMS 正規化、動径次数 n ≤ 10 の66項）から10〜30項。X・Y 別々に選ぶ', '指定'],
    ['係数の大きさ', `標準偏差 σ_{n} = ${cfg.coef_std_order0_nm} × ${cfg.coef_std_decay}^{n} nm（高次ほど小さく）`, '確認＋仮定'],
    ['Mark Offset', `基準パターン（各 Mark ±1〜1.5 nm）＋ Wafer ごとの正規乱数 σ = ${cfg.mark_std} nm`, '指定＋仮定'],
    ['Scan 方向の差', `δ = (${cfg.scan_base[0]}, ${cfg.scan_base[1]}) nm ＋ 正規乱数 σ = ${cfg.scan_std} nm。方向1 +δ/2、方向2 −δ/2`, '指定＋仮定'],
    ['計測ノイズ', '一様分布、幅 a(r) = 1 + 2 (r / r_{max})^{3} nm（中心 ±1 → 最外周 ±3）', '確認＋仮定'],
    ['Wafer 数・Shot 数', `${N_WAFERS.toLocaleString()} 枚 × ${LEVELS.length} 水準（${LEVELS.join(', ')} Shot）`, '指定'],
  ];
  addStyledTable(slide, [
    tableHead(['項目', '設定', '根拠']),
    ...rows.map(([a, b, c]) => [cell(a, { align: 'left', bold: true }), { text: toRuns(b), options: { align: 'left' } }, cell(c, { color: c === '指定' ? C.good : C.muted })]),
  ], MARGIN_X, 1.55, CONTENT_W, [2.3, CONTENT_W - 4.0, 1.7], { fontSize: 13, rowH: 0.56 });
  addFormulaCard(slide, 'trend', MARGIN_X, 6.15, 7.4, 0.7, { fill: C.tint, scale: 0.78, alt: '面内傾向の式' });
  addFormulaCard(slide, 'noise', MARGIN_X + 7.65, 6.15, CONTENT_W - 7.65, 0.7, { fill: C.tint, scale: 0.85, alt: 'ノイズの式' });
}

// =====================================================================
// 8. サンプリング
// =====================================================================
{
  const cons = D.config.constraints;
  const slide = newContentSlide(SECTION.s2, `サンプリング ― 制約付きI最適計画で${lo}〜${hi} Shotを選ぶ`, [
    '学習データにするショットは、制約付きのI最適計画で選びました。',
    'I最適計画は、Wafer全体での平均の予測分散を最小にするショットの組を選ぶ方法です。基準のモデルはXY5次多項式で、XとYの21項です。',
    '制約として、同心円の3つの区画、4つの象限、2つのスキャン方向のそれぞれで、選ぶショット数を全ショットに占める割合のプラスマイナス1に収めました。スキャン方向の制約は、質的変数としてのスキャン方向を推定するために、両方向を必ず含める役割もあります。',
    '選んだショットの全マークを計測します。計画は面内傾向の値によらないので、ショット数ごとに1つ作り、全Waferに共通で使いました。',
    '図は10、20、30、40ショットの計画で、青と橙が計測するショット、白が推定するショットです。',
  ], { source: `計画の基準モデル：XY5次多項式（21項）。交換法（Fedorov型）、初期配置30通りから最良を採用` });
  addFigure(slide, 'fig01_layout_sampling.png', MARGIN_X, 1.5, 8.3, 3.6, 'サンプリング計画', { align: 'left' });
  const rx = MARGIN_X + 8.55;
  const rw = SLIDE_W - MARGIN_X - rx;
  addFormulaCard(slide, 'i_optimal', rx, 1.55, rw, 0.85, { fill: C.tint, scale: 0.85, alt: 'I最適の基準' });
  addBullets(slide, [
    'B_{s}：Shot s の Mark での XY5 多項式（全 Mark で正規直交化）',
    `同心円 ${cons.radial_zone_edges.slice(1, -1).join('・')}（半径比）で3区画`,
    '4象限・Scan 方向2つ',
    `各区画の Shot 数 = 割合 × 選ぶ数 ± ${cons.slack}`,
  ], rx, 2.6, rw, 2.4, { fontSize: 13, space: 8 });
  const colW = (8.3 - 2.0) / LEVELS.length;
  addStyledTable(slide, [
    tableHead(['計測 Shot 数', ...LEVELS.map((n) => `${n}`)]),
    [cell('学習 Mark', { align: 'left', bold: true }), ...LEVELS.map((n) => cell(`${D.plans[String(n)].n_train_marks}`))],
    [cell('推定する Mark', { align: 'left', bold: true }), ...LEVELS.map((n) => cell(`${D.data.n_marks - D.plans[String(n)].n_train_marks}`))],
  ], MARGIN_X, 5.3, 8.3, [2.0, ...LEVELS.map(() => colW)], { fontSize: 12, rowH: 0.42 });
  addCard(slide, rx, 5.2, rw, 1.65, { fill: C.gray });
  addText(slide, '計画は面内傾向の値に依存しないので、Shot 数ごとに1つ作り、全 Wafer で共通に使う（学習点と推定点が全 Wafer で同じ）',
    rx + 0.25, 5.2, rw - 0.5, 1.65, { fontSize: 12.5, valign: 'middle' });
}

// =====================================================================
// 9. 比較した手法
// =====================================================================
{
  const slide = newContentSlide(SECTION.s2, `比較した手法 ― 7系統・${D.run.n_methods}設定`, [
    `比べた手法の一覧です。7つの系統に、カーネルやバリオグラム、説明変数の組み合わせを掛けて、${D.run.n_methods}通りになります。`,
    'GPRは、MATLABのfitrgp関数で使える10種類のカーネルと、3つの説明変数の組、3つの質的変数の扱いを掛けた90通りです。',
    'TPSは平滑化つきの薄板スプライン、KrigingとUniversal Krigingは4つのバリオグラム、GAMはScan方向とMark番号を質的変数として加えます。',
    'XY5次多項式とRTモデルは基底が座標の式で決まっているので、説明変数の組や質的変数は使いません。RTモデルは、XYに換算して5次になるK=4と、K=5の2つを比べました。',
    'ハイパーパラメータの決め方は手法ごとの標準的な方法に合わせました。GPRは周辺尤度の最大化、TPSは一般化交差検証、Krigingは経験バリオグラムへの当てはめ、GAMは制限付き最尤です。',
  ]);
  const rows = [
    ['GPR', 'fitrgp の10カーネル', '3組', 'なし／同時推定／Backfitting', '90', '対数周辺尤度の最大化（fitrgp と同じ）'],
    ['TPS', '平滑化つき薄板スプライン', '3組', '－', '3', '平滑化を GCV で選ぶ'],
    ['Kriging', 'Ordinary、バリオグラム4種', '3組', '－', '12', '経験バリオグラムへ最小二乗（PyKrige 既定）'],
    ['Universal Kriging', 'ドリフト＝説明変数の1次式、4種', '3組', '－', '12', '同上（ドリフトを除いた残差で）'],
    ['GAM', 's(x,y)＋s(r)＋周期 s(T)', '3組', '説明変数に追加', '3', '平滑化を REML で選ぶ'],
    ['XY5次多項式', 'X・Y 各21項', '－', '－', '1', '最小二乗'],
    ['RTモデル', 'R = ρM、T = ρΘ（K = 4, 5）', '－', '－', '2', '最小二乗（X・Y 同時）'],
  ];
  const keys = ['GPR', 'TPS', 'OK', 'UK', 'GAM', 'XY', 'RT'];
  addStyledTable(slide, [
    tableHead(['系統', 'モデル', '説明変数', '質的変数（Scan・Mark）', '設定数', 'ハイパーパラメータ']),
    ...rows.map((row, i) => [
      { text: row[0], options: { align: 'left', bold: true, color: FAMILY_COLOR[keys[i]] } },
      cell(row[1], { align: 'left' }), cell(row[2]), cell(row[3]), cell(row[4], { bold: true }), cell(row[5], { align: 'left' }),
    ]),
  ], MARGIN_X, 1.55, CONTENT_W, [2.0, 3.0, 1.1, 2.4, 0.9, CONTENT_W - 9.4], { fontSize: 12.5, rowH: 0.56 });
  addCard(slide, MARGIN_X, 6.15, CONTENT_W, 0.7, { fill: C.tint });
  addText(slide, '各手法は X と Y を別々に推定（RT モデルのみ X・Y を同時に当てはめ）。説明変数は Wafer 半径 150 mm で割って単位をそろえた',
    MARGIN_X + 0.3, 6.15, CONTENT_W - 0.6, 0.7, { fontSize: 13, valign: 'middle' });
}

// =====================================================================
// 10. GPR
// =====================================================================
{
  const slide = newContentSlide(SECTION.s2, 'GPR ― fitrgp の10カーネルと、質的変数の3つの扱い', [
    'GPRの設定です。',
    'カーネルは、MATLABのfitrgp関数で指定できる10種類です。指数、2乗指数、Matern 3/2、Matern 5/2、有理2次の5種類と、それぞれの説明変数ごとに長さスケールを持つARD版です。',
    'fitrgpの既定と同じく、平均の基底関数の係数は一般化最小二乗で求め、ハイパーパラメータは対数周辺尤度の最大化で決めました。初期値の決め方もfitrgpに合わせています。',
    '質的変数の扱いは3通りです。使わない、効果コードを基底関数に加えて同時に推定する、Backfittingで追い込む、の3つです。',
    'Backfittingは、質的変数の効果を除いた残差でGPRを当てはめ直すことと、GPRの推定を除いた残差で質的変数の効果を求め直すことを、変わらなくなるまで繰り返します。',
  ], { source: '出典：MathWorks「fitrgp」「Kernel (Covariance) Function Options」、Rasmussen & Williams (2006)' });
  const kernels = [
    ['exponential', 'σ_{f}^{2} exp(−r)'],
    ['squaredexponential', 'σ_{f}^{2} exp(−r^{2}/2)'],
    ['matern32', 'σ_{f}^{2} (1+√3 r) exp(−√3 r)'],
    ['matern52', 'σ_{f}^{2} (1+√5 r+5r^{2}/3) exp(−√5 r)'],
    ['rationalquadratic', 'σ_{f}^{2} (1+r^{2}/(2α))^{−α}'],
  ];
  addStyledTable(slide, [
    tableHead(['カーネル（ARD 版あり）', 'k(r)']),
    ...kernels.map(([name, f]) => [cell(name, { align: 'left', bold: true }), { text: toRuns(f), options: { align: 'left' } }]),
  ], MARGIN_X, 1.55, 6.2, [2.6, 3.6], { fontSize: 12.5, rowH: 0.43 });
  addText(slide, 'r：長さスケールで割った距離。等方版は長さスケール1つ、ARD 版は説明変数ごと（T の cos・sin は1つを共有）',
    MARGIN_X, 4.2, 6.2, 0.6, { fontSize: 11.5, color: C.muted });
  addFormulaCard(slide, 'gpr_model', MARGIN_X, 4.85, 6.2, 0.75, { fill: C.tint, scale: 0.98, alt: 'GPR のモデル' });
  addFormulaCard(slide, 'profile_lik', MARGIN_X, 5.75, 6.2, 0.95, { fill: C.tint, scale: 1.0, alt: 'プロファイル尤度' });
  const rx = 7.1;
  const rw = SLIDE_W - MARGIN_X - rx;
  const modes = [
    ['none', '質的変数なし', 'H = 1（定数）。Scan・Mark の差は GPR かノイズに吸収される'],
    ['basis', '基底関数で同時推定', 'H = [1, Scan, Mark] の効果コード。β と超パラメータを同時に推定（fitrgp の BasisFunction に行列を渡すのと同じ）'],
    ['backfit', 'Backfitting', '効果を群平均で初期化 → ①残差で GPR（超パラメータも再推定）→ ②効果を求め直す、を収束まで'],
  ];
  modes.forEach(([key, title, desc], i) => {
    const y = 1.55 + i * 1.32;
    addCard(slide, rx, y, rw, 1.18, { fill: C.gray });
    addNode(slide, rx + 0.42, y + 0.59, 0.44, C[key], String(i + 1), { fontSize: 14 });
    addText(slide, title, rx + 0.85, y + 0.1, rw - 1.0, 0.4, { fontSize: 15, bold: true, valign: 'middle' });
    addText(slide, desc, rx + 0.85, y + 0.5, rw - 1.05, 0.65, { fontSize: 12 });
  });
  addFormulaCard(slide, 'backfit', rx, 5.6, rw, 0.6, { fill: C.tint, scale: 0.92, alt: 'Backfitting の更新式' });
  addText(slide, 'F：Scan・Mark の効果コード（学習点で中心化）。②の内側の交互当てはめは収束値（GLS 解）を直接計算',
    rx, 6.3, rw, 0.55, { fontSize: 11.5, color: C.muted });
}

// =====================================================================
// 11. その他の手法
// =====================================================================
{
  const slide = newContentSlide(SECTION.s2, 'TPS・Kriging・GAM・XY5・RT ― 定義とパラメータの決め方', [
    'GPR以外の手法です。',
    'TPSは、薄板スプラインに平滑化を加えたもので、平滑化の強さを一般化交差検証で選びます。3次元以上の説明変数にも同じ基底を使いました。',
    'Krigingは、通常のKrigingとUniversal Krigingの2つです。バリオグラムは線形、ガウス、べき、指数の4種類で、式と当てはめ方はPyKrigeの既定に合わせました。経験バリオグラムを6つの距離区間で求め、最小二乗で当てはめます。',
    'GAMは、XとYの2次元の平滑項に、半径の平滑項と、方位角の周期的な平滑項を加え、Scan方向とMark番号を質的変数として入れました。平滑化パラメータは制限付き最尤で選びます。',
    'RTモデルは、変位を半径方向と接線方向に分け、それぞれ局所倍率と局所回転のマップをZernike多項式で表すモデルです。',
  ], { source: '出典：Wahba (1990)、Cressie (1993)、PyKrige ドキュメント、Wood (2017)、Eilers & Marx (1996)、ASML US10495990B2' });
  const cards = [
    ['TPS', C.tps, C.tpsTint, 'tps', '平滑化 λ を GCV で選ぶ。多項式部分は説明変数の1次式'],
    ['Kriging / Universal Kriging', C.ok, C.okTint, 'kriging', 'f = 1（通常）または [1, z]（Universal）。バリオグラム：linear・gaussian・power・exponential（PyKrige の式）'],
    ['GAM', C.gam, C.gamTint, 'gam', 'P-spline（各8基底）。s(x,y) はテンソル積、s_{∘}(T) は周期。λ は REML'],
    ['RTモデル', C.rt, C.rtTint, 'rt', 'K = 4（34係数、XY換算5次）と K = 5（46係数）。並進・非対称倍率・直交度を含む'],
  ];
  const w = (CONTENT_W - 0.35) / 2;
  const h = 2.5;
  cards.forEach(([title, color, tint, formula, desc], i) => {
    const x = MARGIN_X + (i % 2) * (w + 0.35);
    const y = 1.55 + Math.floor(i / 2) * (h + 0.25);
    addCard(slide, x, y, w, h, { fill: C.gray });
    addChip(slide, x + 0.25, y + 0.18, color, title, { fontSize: 15, w: w - 0.5 });
    addFormulaCard(slide, formula, x + 0.25, y + 0.65, w - 0.5, 0.85, { fill: tint, scale: Math.min(0.92, (w - 0.7) / formulaSize(formula).w), alt: title });
    addText(slide, desc, x + 0.3, y + 1.65, w - 0.6, 0.8, { fontSize: 12.5 });
  });
  addText(slide, 'XY5次多項式：X・Y それぞれ x^{a}y^{b}（a + b ≤ 5）の21項を最小二乗', MARGIN_X, 6.62, CONTENT_W, 0.35, { fontSize: 12.5, color: C.muted });
}

// =====================================================================
// 12. 説明変数と評価指標
// =====================================================================
{
  const slide = newContentSlide(SECTION.s2, '説明変数と評価指標 ― T は方位角、精度は真値と比べる4指標', [
    '説明変数は3通りです。X, Yだけ、X, Yに半径を加えたもの、さらに接線方向の位置Tを加えたものです。',
    'Tは、ASMLのR&Tモデルの接線方向の位置で、方位角thetaとして座標から計算しました。',
    'ただし角度はプラスマイナス180度でつながっているので、距離を使うGPR、TPS、Krigingでは、cos thetaとsin thetaの2列に展開しました。ARDカーネルでは、この2列に1つの長さスケールを共有させています。GAMでは周期的なスプラインで扱いました。',
    '評価は、未計測ショットの全マークで、ノイズを含まない真値と推定値を比べました。',
    '自由度調整済み決定係数のpには、学習点での平滑化行列のトレースから切片の1を引いた値を使いました。平滑化の強い手法ほどpが小さくなり、柔らかいモデルほど罰を受けます。',
  ]);
  const sets = [
    ['X, Y', 'x / R_{w}, y / R_{w}', C.gpr],
    ['X, Y, 半径', '＋ r / R_{w}', C.gpr],
    ['X, Y, 半径, T', '＋ (cos θ, sin θ)、GAM は周期スプライン', C.gpr],
  ];
  addText(slide, '説明変数の組', MARGIN_X, 1.55, 6, 0.4, { fontSize: 16, bold: true, color: C.indigo });
  const shades = ['86B6EF', '2A78D6', '104281'];
  sets.forEach(([title, desc], i) => {
    const y = 2.05 + i * 0.85;
    addCard(slide, MARGIN_X, y, 6.0, 0.72, { fill: C.gray });
    slide.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: MARGIN_X + 0.2, y: y + 0.2, w: 0.32, h: 0.32, rectRadius: 0.05, fill: { color: shades[i] }, line: { color: shades[i], width: 0.5 } });
    addText(slide, title, MARGIN_X + 0.7, y, 1.9, 0.72, { fontSize: 15, bold: true, valign: 'middle' });
    addText(slide, desc, MARGIN_X + 2.6, y, 3.3, 0.72, { fontSize: 13, valign: 'middle' });
  });
  addFormulaCard(slide, 'theta', MARGIN_X, 4.7, 6.0, 0.65, { fill: C.tint, scale: 0.9, alt: 'T = θ' });
  addText(slide, 'T は ASML R&T の接線方向 e_{T} = (−sin θ, cos θ) に沿った位置。位置ベクトル自体の T 成分は常に 0 なので角度を使う',
    MARGIN_X, 5.45, 6.0, 0.8, { fontSize: 12, color: C.muted });
  const rx = 7.0;
  const rw = SLIDE_W - MARGIN_X - rx;
  addText(slide, '評価指標（未計測 Shot の全 Mark、真値と比較）', rx, 1.55, rw, 0.4, { fontSize: 16, bold: true, color: C.indigo });
  addFormulaCard(slide, 'r2', rx, 2.05, rw, 0.8, { fill: C.tint, scale: 0.95, alt: 'R2' });
  addFormulaCard(slide, 'adj_r2', rx, 2.95, rw, 0.8, { fill: C.tint, scale: 0.9, alt: '調整済みR2' });
  addFormulaCard(slide, 'rmse_mae', rx, 3.85, rw, 0.8, { fill: C.tint, scale: 0.9, alt: 'RMSE MAE' });
  addBullets(slide, [
    'n：推定する Mark 数、S：学習点での平滑化行列（有効自由度 tr(S)）',
    'X・Y を合わせた値を主に示す（R² の分母は軸ごとの平均からの偏差）',
    `外周（半径 ≥ 120 mm、${D.data.n_outer_marks} Mark）と内側の RMSE も別に集計`,
  ], rx, 4.85, rw, 1.9, { fontSize: 12.5, space: 6 });
}

// =====================================================================
// 13. 結果：全体像
// =====================================================================
{
  const families = FAMILY_ORDER;
  const slide = newContentSlide(SECTION.s3, `全体像 ― ${factorHelpsFrom} Shot 以上は GPR が最良。${lo} Shot では TPS と同程度`, [
    '結果の全体像です。系統ごとに、全ショット数を通して平均の誤差が最も小さい設定を1つ選び、ショット数との関係を描きました。',
    `GPRは${factorHelpsFrom}ショット以上で最も良く、RMSEは${mid}ショットで${f2(familyRmse('GPR', mid))}、${hi}ショットで${f2(familyRmse('GPR', hi))}ナノメートルです。`,
    `${lo}ショットでは、この設定のGPRは${f2(familyRmse('GPR', lo))}ナノメートルで、TPSの${f2(familyRmse('TPS', lo))}と同程度かやや劣ります。${lo}ショットで最も良かったGPRは質的変数を入れない設定で、${f2(gprMode(lo, 'none').rmse)}ナノメートルでした。`,
    `質的変数を含むGAMは、ショット数が増えるとGPRに近づき、${hi}ショットで${f2(familyRmse('GAM', hi))}ナノメートルでした。`,
    `質的変数を使わないTPSとKrigingは、ショット数を増やしても${f1(familyRmse('TPS', hi))}ナノメートル前後で頭打ちになります。Mark番号ごとのOffsetを表せないためです。`,
    `XY5次とRTモデルは、高次のZernike成分を表せず、${hi}ショットでも${f1(familyRmse('XY', hi))}から${f1(familyRmse('RT', hi))}ナノメートルが残りました。`,
  ], { source: `系統ごとに全 Shot 数の平均 RMSE が最小の設定を1つ選んで表示（Shot 数で設定を変えない）。${N_WAFERS.toLocaleString()} 枚の平均` });
  const chartW = 7.9;
  slide.addChart(pres.charts.LINE, families.map((f) => ({ name: FAMILY_LABEL[f], labels: levelLabels, values: LEVELS.map((n) => familyRmse(f, n)) })), {
    x: MARGIN_X, y: 1.45, w: chartW, h: 5.45, ...chartBase(),
    chartColors: families.map((f) => FAMILY_COLOR[f]), lineSize: 2.2, lineDataSymbol: 'circle', lineDataSymbolSize: 7,
    showTitle: true, title: '推定誤差 RMSE（X・Y）[nm]',
    showCatAxisTitle: true, catAxisTitle: '計測 Shot 数', valAxisMinVal: 0, valAxisLabelFormatCode: '0.0',
    showLegend: true, legendPos: 'b',
  });
  const rx = MARGIN_X + chartW + 0.3;
  const rw = SLIDE_W - MARGIN_X - rx;
  addStyledTable(slide, [
    tableHead(['系統（最良の設定）', `${lo}`, `${mid}`, `${hi}`]),
    ...families.map((f) => [
      { text: FAMILY_LABEL[f], options: { align: 'left', bold: true, color: FAMILY_COLOR[f] } },
      cell(f2(familyRmse(f, lo))), cell(f2(familyRmse(f, mid))), cell(f2(familyRmse(f, hi))),
    ]),
  ], rx, 1.55, rw, [rw - 2.25, 0.75, 0.75, 0.75], { fontSize: 12, rowH: 0.4 });
  addBullets(slide, families.slice(0, 5).map((f) => `${FAMILY_LABEL[f]}：${fixed(f).label.replace(`${FAMILY_LABEL[f]} `, '').replace(`${FAMILY_LABEL[f]}｜`, '')}`),
    rx, 4.95, rw, 1.9, { fontSize: 10.5, space: 3, color: C.muted });
}

// =====================================================================
// 14. 系統×説明変数のヒートマップ
// =====================================================================
{
  const slide = newContentSlide(SECTION.s3, '系統×説明変数×質的変数 ― 差を生むのは質的変数と手法', [
    '手法の系統、説明変数、GPRの質的変数の扱いの組み合わせごとに、平均のRMSEを並べました。各行は、その組み合わせの中で最も良いカーネルやバリオグラムです。',
    '色が濃いほど誤差が大きいことを表します。',
    `大きな差を生んでいるのは、質的変数を入れるかどうかと、手法の系統です。GPRで質的変数を入れた行は、${mid}ショット以上でほかの行より明らかに小さくなっています。`,
    '説明変数の違い、つまり同じ系統の3行の違いは、質的変数や系統の違いに比べると小さいです。',
    `${lo}ショットでは、質的変数を入れたGPRより、入れないGPRやTPSの方が良い場合があります。点が少ないと、質的変数の効果をうまく推定できないためです。`,
  ], { source: '各行：その組み合わせで全 Shot 数の平均 RMSE が最小のカーネル・バリオグラムを表示。値は 1000 枚の平均 RMSE（X・Y）[nm]' });
  addFigure(slide, 'fig04_family_feature_heatmap.png', MARGIN_X, 1.45, CONTENT_W, 5.5, '系統×説明変数のRMSE');
}

// =====================================================================
// 15. Shot数ごとの最良
// =====================================================================
{
  const slide = newContentSlide(SECTION.s3, 'Shot数ごとの最良 ― 統計的に差がない設定まで含めて見る', [
    'ショット数ごとに、平均のRMSEが最も小さい設定と、それと統計的に差がない設定の数を示します。',
    '差がないかどうかは、同じWaferどうしの差の95パーセント信頼区間がゼロを含むかで判定しました。',
    `最良の設定はショット数によって入れ替わりますが、${hi}ショットまで、ほぼGPRで質的変数を入れたものです。`,
    '上位は、カーネルの違いより、質的変数を入れるかどうかで決まっています。',
  ], { source: '差がない：同じ Wafer どうしの RMSE の差の 95% 信頼区間が 0 を含む（1000 枚）' });
  const rows = LEVELS.map((n) => {
    const r = rec(n);
    return [
      cell(`${n}`, { bold: true }),
      cell(r.best_label, { align: 'left' }),
      cell(f2(r.best_rmse), { bold: true }),
      cell(`${r.n_tied}`),
      cell(r.tied_families.map((f) => FAMILY_LABEL[f].replace('Universal Kriging', 'UK')).join('・'), { align: 'left' }),
    ];
  });
  addStyledTable(slide, [tableHead(['Shot 数', '最良の設定', 'RMSE [nm]', '差がない設定数', '差がない設定の系統']), ...rows],
    MARGIN_X, 1.55, CONTENT_W, [1.1, 6.0, 1.3, 1.7, CONTENT_W - 10.1], { fontSize: 12, rowH: 0.5 });
  addCard(slide, MARGIN_X, 5.75, CONTENT_W, 1.1, { fill: C.tint });
  const top = D.ranking_top[0];
  addText(slide, `全 Shot 数の平均で1位：${top.label}（平均 RMSE ${f2(top.avg)} nm）。2位以下：${D.ranking_top.slice(1, 4).map((t) => t.label).join('、')}`,
    MARGIN_X + 0.3, 5.75, CONTENT_W - 0.6, 1.1, { fontSize: 13, valign: 'middle' });
}

// =====================================================================
// 16. 説明変数の効果
// =====================================================================
{
  const comparisonRows = ['GPR', 'TPS', 'OK', 'UK', 'GAM'];
  const slide = newContentSlide(SECTION.s3, '説明変数の効果 ― 半径は数%効き、T を加えると悪化する', [
    '説明変数を足した効果です。同じWaferで、X, Yだけの場合とのRMSEの比を、系統ごとの設定の平均で示しました。マイナスが改善です。',
    `GPRでは、半径を足すと${mid}ショットで${signed(feRel('XYR-XY', 'GPR', mid))}パーセントと良くなりましたが、さらにTを足すと${signed(feRel('XYRT-XY', 'GPR', mid))}パーセントと、X, Yだけより悪くなりました。`,
    `TPSとKrigingでも、Tを足すと悪化しました。TPSの${mid}ショットで${signed(feRel('XYRT-XY', 'TPS', mid))}パーセントです。値の変化に関係の薄い次元が距離に加わると、近さの判断がずれるためと考えられます。`,
    `GAMでは、半径や周期的なTの項は罰則で抑えられ、影響は${signed(feRel('XYRT-XY', 'GAM', mid))}パーセント程度でした。`,
    '右の表は、半径を足したとき有意に良くなった設定、悪くなった設定、差がなかった設定の数です。',
  ], { source: '値：同じ Wafer どうしの RMSE の比の平均（系統内のカーネル・バリオグラム・質的変数の扱いを平均）。マイナス＝改善' });
  addFigure(slide, 'fig05_feature_effect.png', MARGIN_X, 1.45, CONTENT_W, 2.85, '説明変数の効果');
  addStyledTable(slide, [
    tableHead(['系統', `半径を追加（${lo}/${mid}/${hi}）`, `半径＋T（${lo}/${mid}/${hi}）`]),
    ...comparisonRows.map((f) => [
      { text: FAMILY_LABEL[f], options: { align: 'left', bold: true, color: FAMILY_COLOR[f] } },
      cell([lo, mid, hi].map((n) => signed(feRel('XYR-XY', f, n))).join(' / ') + ' %'),
      cell([lo, mid, hi].map((n) => signed(feRel('XYRT-XY', f, n))).join(' / ') + ' %'),
    ]),
  ], MARGIN_X, 4.45, 7.6, [2.0, 2.8, 2.8], { fontSize: 12, rowH: 0.38 });
  const rx = MARGIN_X + 7.9;
  const rw = SLIDE_W - MARGIN_X - rx;
  const sumCounts = (comparison, key) => LEVELS.reduce((s, n) => s + (D.feature_effect_counts[comparison][String(n)][key] || 0), 0);
  addStyledTable(slide, [
    tableHead(['設定ごとの判定', '改善', '悪化', '差なし']),
    ...['XYR-XY', 'XYRT-XY', 'XYRT-XYR'].map((comparison) => [
      cell({ 'XYR-XY': '半径を追加', 'XYRT-XY': '半径＋T を追加', 'XYRT-XYR': 'T を追加（半径あり）' }[comparison], { align: 'left', bold: true }),
      cell(`${sumCounts(comparison, 'better')}`, { color: C.good, bold: true }),
      cell(`${sumCounts(comparison, 'worse')}`, { color: C.bad, bold: true }),
      cell(`${sumCounts(comparison, 'ns')}`, { color: C.muted }),
    ]),
  ], rx, 4.45, rw, [rw - 2.4, 0.8, 0.8, 0.8], { fontSize: 12, rowH: 0.42 });
  addText(slide, `件数：${LEVELS.length} 水準 × 系統内の設定（カーネル・バリオグラム・質的変数の扱い）。同じ Wafer どうしの差の 95% 信頼区間で判定`,
    rx, 6.25, rw, 0.6, { fontSize: 10.5, color: C.muted });
}

// =====================================================================
// 17. なぜ T が効かないか（ARD）
// =====================================================================
{
  const T = D.ard_usage['XYRT|T'];
  const Rr = D.ard_usage['XYR|r'];
  const slide = newContentSlide(SECTION.s3, 'T が効かない理由 ― ARD は T をほとんど使わない', [
    'Tが効かない理由を、ARDカーネルの長さスケールから見ます。',
    'ARDカーネルは、説明変数ごとに長さスケールを推定します。長さスケールが上限に張り付くと、その変数は推定にほとんど使われていないことになります。',
    `X, Y, 半径, Tの組では、Tの長さスケールが上限になった割合が、${lo}ショットで${pct(T[String(lo)])}パーセント、${hi}ショットで${pct(T[String(hi)])}パーセントでした。`,
    `一方、半径が上限になった割合は${pct(Rr[String(lo)])}から${pct(Rr[String(hi)])}パーセントで、半径は多くの場合に使われています。`,
    'X, Yがあれば方位角はすでに表せるので、Tを加えても新しい情報はありません。また、今回の模擬データには、方位方向にだけ急に変わるような成分はありません。',
  ], { source: '長さスケールの上限は 1000（説明変数は Wafer 半径で割った単位）。ARD カーネル5種・質的変数3通り・X と Y の当てはめ全体の割合' });
  addFigure(slide, 'fig13_ard_usage.png', MARGIN_X, 1.5, 7.6, 4.2, 'ARDで使われなかった割合', { align: 'left' });
  const rx = MARGIN_X + 7.9;
  const rw = SLIDE_W - MARGIN_X - rx;
  addStat(slide, rx, 1.55, rw, 2.3, `${pct(T[String(hi)])}%`, `T を使わなかった割合（${hi} Shot）`,
    `${lo} Shot では ${pct(T[String(lo)])}%。T の長さスケールが上限 = T の方向には値が変わらないとみなした`, { fill: C.gprTint, color: C.gpr });
  addBullets(slide, [
    'X, Y があれば方位角は表せる（T は X, Y の関数）',
    '模擬データに方位方向だけに急に変わる成分はない',
    '等方カーネル・TPS・Kriging では、効かない次元が距離をゆがめて悪化する',
  ], rx, 4.1, rw, 2.7, { fontSize: 13, space: 10 });
}

// =====================================================================
// 18. 質的変数の効果
// =====================================================================
{
  const modes = ['none', 'basis', 'backfit'];
  const gm = (n, m) => D.gpr_mode_rmse[String(n)][m].mean;
  const slide = newContentSlide(SECTION.s3, `質的変数の効果 ― ${factorHelpsFrom} Shot 以上で大きく下がり、${lo} Shot では逆効果`, [
    'GPRで、Scan方向とMark番号を質的変数として入れた効果です。',
    `30通りの設定の平均で見ると、質的変数を基底関数で同時に推定すると、${hi}ショットでRMSEが${f2(gm(hi, 'none'))}から${f2(gm(hi, 'basis'))}ナノメートルに下がりました。${signed(fxRel('basis-none', hi))}パーセントです。`,
    `質的変数を入れないと、Mark番号ごとのOffsetがそのまま誤差として残るため、ショット数を増やしても下がり方が止まります。`,
    `一方、${lo}ショットでは${signed(fxRel('basis-none', lo))}パーセントで、${FX['basis-none'][String(lo)].sig === 'worse' ? 'かえって悪くなりました' : '効果は小さくなりました'}。点が40個しかないと、スキャン方向の差やマークごとの差を、面内の傾向と区別しにくいためです。`,
    '外周では、内側よりも誤差が大きく、質的変数の効果も外周の方が小さくなります。',
  ], { source: 'GPR 30 設定（10 カーネル × 説明変数3組）の平均。同時推定と Backfitting の線はほぼ重なる' });
  slide.addChart(pres.charts.LINE, modes.map((m) => ({ name: MODE_LABEL[m], labels: levelLabels, values: LEVELS.map((n) => gm(n, m)) })), {
    x: MARGIN_X, y: 1.45, w: 6.3, h: 5.4, ...chartBase(),
    chartColors: [C.none, C.basis, C.backfit], lineSize: 2.2, lineDataSymbol: 'circle', lineDataSymbolSize: 7,
    showTitle: true, title: 'GPR の RMSE（X・Y）[nm]、30 設定の平均',
    showCatAxisTitle: true, catAxisTitle: '計測 Shot 数', valAxisMinVal: 0, valAxisLabelFormatCode: '0.0',
    showLegend: true, legendPos: 'b',
  });
  addFigure(slide, 'fig06_factor_edge.png', MARGIN_X + 6.5, 1.45, CONTENT_W - 6.5, 2.55, '質的変数の扱いと外周');
  const rows = LEVELS.map((n) => [
    cell(`${n}`, { bold: true }),
    cell(`${signed(fxRel('basis-none', n))}%`, { color: FX['basis-none'][String(n)].sig === 'better' ? C.good : FX['basis-none'][String(n)].sig === 'worse' ? C.bad : C.muted, bold: true }),
    cell(`${pct(FX['basis-none'][String(n)].win)}%`),
    cell(`${signed(fxRel('backfit-basis', n), 2)}%`),
  ]);
  addStyledTable(slide, [tableHead(['Shot', '同時推定 − なし', '改善した Wafer', 'Backfit − 同時']), ...rows],
    MARGIN_X + 6.5, 4.05, CONTENT_W - 6.5, [0.9, 1.9, 1.8, CONTENT_W - 6.5 - 4.6], { fontSize: 11.5, rowH: 0.31 });
  addText(slide, '表：同じ Wafer どうしの RMSE の比の平均（マイナス＝改善）', MARGIN_X + 6.5, 6.62, CONTENT_W - 6.5, 0.3, { fontSize: 10.5, color: C.muted });
}

// =====================================================================
// 19. Backfitting と同時推定
// =====================================================================
{
  const order = D.backfit_order;
  const classicKeys = ['classic_factor_first', 'classic_gp_first'];
  const fewLevels = [lo, mid];
  const classicIter = order ? fewLevels.flatMap((n) => classicKeys.map((k) => order[String(n)][k].iter_mean)) : [];
  const classicFail = order ? fewLevels.flatMap((n) => classicKeys.map((k) => 1 - order[String(n)][k].converged)) : [];
  const slide = newContentSlide(SECTION.s3, 'Backfitting ― 収束すれば同時推定と同じ解。教科書どおりでは収束が遅い', [
    'Backfittingで追い込んだ場合と、基底関数として同時に推定した場合の比較です。',
    `同じWafer、同じ設定で比べると、RMSEの差が0.01ナノメートル未満の場合が${pct(BV.share_within_001)}パーセント、0.1ナノメートル未満が${pct(BV.share_within_01)}パーセントでした。反復は平均${f1(BV.iter_mean)}回で収束しました。`,
    '理由は、Backfittingが、同じ尤度をハイパーパラメータと平均の係数について交互に最大化する方法だからです。収束すれば、同時に最大化した解と同じ点に着きます。ハイパーパラメータを固定した場合、交互の当てはめの極限が一般化最小二乗の解に一致することも、テストで確かめました。',
    order ? `補足として、1回の反復でGPRと質的変数を1回ずつ当てはめ直す、教科書どおりのBackfittingを${D.backfit_order_n_wafers}枚で試しました。${lo}ショットと${mid}ショットでは収束が遅く、平均${f0(Math.min(...classicIter))}から${f0(Math.max(...classicIter))}回かかり、上限の300回でも${f0(100 * Math.min(...classicFail))}から${f0(100 * Math.max(...classicFail))}パーセントが収束しませんでした。収束しなかったWaferは誤差が大きく、平均のRMSEも悪くなりました。GPRがMark番号ごとの差の一部を面内の傾向として表せてしまうため、交互の当てはめが少しずつしか進まないと考えられます。${hi}ショットでは約${f0(order[String(hi)].classic_gp_first.iter_mean)}回で収束し、同時推定と同じ結果でした。` : '',
    '本計算のBackfittingは、ハイパーパラメータを固定したときの交互の当てはめの収束値を直接計算しているので、数回で収束します。',
    '実務では、Backfittingを使う必要はなく、基底関数として同時に推定すれば十分です。',
  ].filter(Boolean), { source: '差：同じ Wafer・同じカーネル・同じ説明変数での RMSE（Backfitting − 同時推定）' });
  const w = (CONTENT_W - 2 * 0.35) / 3;
  addStat(slide, MARGIN_X, 1.55, w, 2.2, `${pct(BV.share_within_001, 1)}%`, '差が 0.01 nm 未満の割合', `0.1 nm 未満は ${pct(BV.share_within_01, 1)}%。平均の差 ${signed(BV.mean_diff, 4)} nm`, { fill: C.gprTint, color: C.gpr });
  addStat(slide, MARGIN_X + w + 0.35, 1.55, w, 2.2, `${f1(BV.iter_mean)} 回`, '収束までの反復（平均）', `最大 ${BV.iter_max} 回、収束した割合 ${pct(BV.converged_rate, 1)}%`, { fill: C.tpsTint, color: C.backfit });
  addStat(slide, MARGIN_X + 2 * (w + 0.35), 1.55, w, 2.2, '同じ尤度', 'を交互に最大化（座標上昇法）', '超パラメータ θ と平均の係数 (β, γ) を交互に更新 → 同時最大化と同じ停留点', { fill: C.gray, color: C.indigo });
  if (order) {
    const variants = [['basis', '同時推定'], ['backfit', 'Backfitting（本計算）'], ['classic_factor_first', '教科書どおり（質的変数を先）'], ['classic_gp_first', '教科書どおり（GPR を先）']];
    addStyledTable(slide, [
      tableHead(['方法', ...[lo, mid, hi].map((n) => `${n} Shot：RMSE／反復`), '収束率（' + lo + ' Shot）']),
      ...variants.map(([key, name]) => [
        cell(name, { align: 'left', bold: true }),
        ...[lo, mid, hi].map((n) => cell(`${f3(order[String(n)][key].rmse)}／${key === 'basis' ? '－' : f1(order[String(n)][key].iter_mean)}`)),
        cell(key === 'basis' ? '－' : `${pct(order[String(lo)][key].converged)}%`),
      ]),
    ], MARGIN_X, 4.0, CONTENT_W, [3.6, 2.2, 2.2, 2.2, CONTENT_W - 10.2], { fontSize: 12, rowH: 0.42 });
    addText(slide, `補足検証：${D.backfit_order_n_wafers} 枚、カーネル2種（squaredexponential・matern52）× 説明変数 X, Y, 半径、反復の上限 300 回。教科書どおり＝1回の反復で GPR と質的変数を1回ずつ当てはめ直す。収束率は ${lo} Shot の値`,
      MARGIN_X, 6.25, CONTENT_W, 0.6, { fontSize: 11.5, color: C.muted });
  }
}

// =====================================================================
// 20. カーネル
// =====================================================================
{
  const kr = D.kernel_rank;
  const slide = newContentSlide(SECTION.s3, `カーネル ― ${kr[0].kernel} が最良、exponential は不利`, [
    'GPRのカーネルの比較です。質的変数を同時に推定した場合について、カーネルと説明変数の組ごとの平均RMSEを、最良との比の色で示しました。',
    `全ショット数の平均で最も良かったのは${kr[0].kernel}で、${kr[1].kernel}、${kr[2].kernel}が続きました。`,
    `最も悪かったのは${kr[kr.length - 1].kernel}です。指数カーネルは関数がなめらかでないため、Zernikeのようななめらかな面内傾向に対して、ノイズまで追いかけやすくなります。`,
    'ARD版と等方版の差は小さく、ARDで長さスケールを増やしても大きな改善はありませんでした。',
  ], { source: '質的変数は基底関数で同時推定。色は各 Shot 数での最良との比、数値は 1000 枚の平均 RMSE（X・Y）[nm]' });
  addFigure(slide, 'fig07_kernel_heatmap.png', MARGIN_X, 1.45, 8.7, 5.45, 'カーネル比較', { align: 'left' });
  const rx = MARGIN_X + 8.9;
  const rw = SLIDE_W - MARGIN_X - rx;
  addStyledTable(slide, [
    tableHead(['順位', 'カーネル', '平均']),
    ...kr.map((k, i) => [cell(`${i + 1}`), cell(k.kernel, { align: 'left', fontSize: 10 }), cell(f2(k.avg))]),
  ], rx, 1.55, rw, [0.5, rw - 1.2, 0.7], { fontSize: 11, rowH: 0.42 });
  addText(slide, '平均：全 Shot 数・説明変数3組の RMSE の平均 [nm]', rx, 6.3, rw, 0.5, { fontSize: 10.5, color: C.muted });
}

// =====================================================================
// 21. Kriging
// =====================================================================
{
  const vr = D.variogram_rank;
  const nug = D.kriging_nugget_median;
  const gn = D.gpr_noise_median;
  const slide = newContentSlide(SECTION.s3, 'Kriging ― 予測式は GPR と同じでも、パラメータの決め方で大きく劣る', [
    'KrigingとUniversal Krigingの、バリオグラムごとの比較です。',
    `最も良かったのは${FAMILY_LABEL[vr[0].family]}の${vr[0].variogram}バリオグラムでしたが、それでもGPRより大きく劣りました。`,
    'Krigingの予測式は、共分散を与えればGPRと同じです。違いはパラメータの決め方で、Krigingは距離の区間ごとの経験バリオグラムに曲線を当てはめるのに対し、GPRは周辺尤度を最大化します。',
    `PyKrigeの既定の6区間では、最初の区間がおよそ50ミリと広く、ナゲット、つまりノイズにあたる値が過大に推定されました。ナゲットの中央値は${lo}ショットで${f1(nug[String(lo)])}平方ナノメートルで、GPRが推定したノイズの分散、およそ${f1(gn[String(lo)] ** 2)}平方ナノメートルより大きく、推定が平らになりすぎます。`,
    'ガウス型のバリオグラムは、ナゲットがゼロになると計算が不安定になり、誤差が大きくなりました。',
  ], { source: 'バリオグラムの式と当てはめ方は PyKrige の既定（6区間、soft L1 損失）。ナゲット・GPR のノイズは X・Y の中央値' });
  addFigure(slide, 'fig08_variogram.png', MARGIN_X, 1.45, 8.9, 3.45, 'バリオグラムの比較', { align: 'left' });
  addStyledTable(slide, [
    tableHead(['Shot 数', ...LEVELS.map((n) => `${n}`)]),
    [cell('Kriging ナゲット [nm²]', { align: 'left', bold: true }), ...LEVELS.map((n) => cell(f1(nug[String(n)])))],
    [cell('GPR ノイズ分散 σn² [nm²]', { align: 'left', bold: true }), ...LEVELS.map((n) => cell(f2(gn[String(n)] ** 2)))],
  ], MARGIN_X, 5.1, 8.9, [2.6, ...LEVELS.map(() => 6.3 / LEVELS.length)], { fontSize: 11.5, rowH: 0.4 });
  const rx = MARGIN_X + 9.2;
  const rw = SLIDE_W - MARGIN_X - rx;
  addStyledTable(slide, [
    tableHead(['手法｜バリオグラム', '平均']),
    ...vr.map((v) => [cell(`${v.family === 'OK' ? 'Kriging' : 'UK'}｜${v.variogram}`, { align: 'left', color: FAMILY_COLOR[v.family], bold: true }), cell(f2(v.avg))]),
  ], rx, 1.55, rw, [rw - 0.8, 0.8], { fontSize: 11, rowH: 0.4 });
  addText(slide, '平均：全 Shot 数・説明変数3組の RMSE [nm]', rx, 5.35, rw, 0.5, { fontSize: 10.5, color: C.muted });
}

// =====================================================================
// 22. 4つの指標
// =====================================================================
{
  const ag = D.metric_agreement;
  const slide = newContentSlide(SECTION.s3, '4つの指標 ― 順位はほぼ一致。調整済み R² は柔らかいモデルに厳しい', [
    '決定係数、自由度調整済み決定係数、RMSE、MAEの4つの指標の比較です。',
    'どの指標でも、系統の順序はほぼ同じでした。',
    `RMSEの順位との順位相関は、MAEで${f3(ag[String(mid)].MAE.spearman)}、決定係数で${f3(ag[String(mid)].R2.spearman)}、自由度調整済み決定係数で${f3(ag[String(mid)].adjR2.spearman)}でした（${mid}ショット）。`,
    '自由度調整済み決定係数は、有効自由度の大きい手法、たとえば指数カーネルのGPRや、ナゲットが小さいKrigingに厳しくなります。同じ精度なら、より単純なモデルを選ぶための指標として使えます。',
    'ただし、推定精度そのものを比べるならRMSEかMAEを、ばらつきの何割を説明できたかを見るなら決定係数を使うのが分かりやすいです。',
  ], { source: '系統ごとの最良の設定（全 Shot 数の平均 RMSE で選んだもの）。順位相関は全 123 設定の平均値の Spearman 相関' });
  addFigure(slide, 'fig09_metrics.png', MARGIN_X, 1.45, CONTENT_W, 2.95, '4指標の比較');
  const metrics = [['MAE', 'MAE'], ['R2', '決定係数'], ['adjR2', '調整済み決定係数']];
  addStyledTable(slide, [
    tableHead(['指標', ...LEVELS.map((n) => `${n}`), 'RMSE と最良が同じ']),
    ...metrics.map(([key, name]) => [
      cell(name, { align: 'left', bold: true }),
      ...LEVELS.map((n) => cell(f2(ag[String(n)][key].spearman))),
      cell(`${LEVELS.filter((n) => ag[String(n)][key].same).length} / ${LEVELS.length}`),
    ]),
  ], MARGIN_X, 4.65, CONTENT_W, [2.6, ...LEVELS.map(() => 1.05), CONTENT_W - 2.6 - 1.05 * LEVELS.length], { fontSize: 12, rowH: 0.42 });
  addText(slide, '表の値：RMSE による順位との Spearman 順位相関（Shot 数ごと、123 設定）', MARGIN_X, 6.5, CONTENT_W, 0.35, { fontSize: 11, color: C.muted });
}

// =====================================================================
// 23. 外周と内側
// =====================================================================
{
  const e = (n, f) => D.edge[String(n)][f];
  const slide = newContentSlide(SECTION.s3, '外周 ― 誤差は内側の約2倍。外周は推定が外挿になりノイズも大きい', [
    '外周、半径120ミリ以上のマークと、内側のマークに分けた誤差です。',
    `どの手法も外周の方が誤差が大きく、GPRの${mid}ショットで外周${f2(e(mid, 'GPR').outer)}、内側${f2(e(mid, 'GPR').inner)}ナノメートルでした。`,
    '外周では、計測ノイズが大きいことに加えて、推定が計測点の外側への外挿になるためです。',
    'XY5次多項式とRTモデルは、外周で特に大きく外れます。高次の多項式は端で大きく振れるためです。',
    '外周の精度を上げるには、外周の計測ショットを増やす制約や、外周の計測誤差を重みとして入れる方法が考えられます。今回は評価していません。',
  ], { source: '系統ごとの最良の設定。外周：Mark の半径 ≥ 120 mm' });
  addFigure(slide, 'fig10_edge_inner.png', MARGIN_X, 1.45, 8.8, 3.6, '外周と内側', { align: 'left' });
  const tw = CONTENT_W - 9.0;
  addStyledTable(slide, [
    tableHead(['系統', `${lo} Shot 外周／内側`, `${hi} Shot 外周／内側`]),
    ...FAMILY_ORDER.map((f) => [
      { text: FAMILY_LABEL[f].replace('Universal Kriging', 'Univ. Kriging').replace('XY5次多項式', 'XY5次'), options: { align: 'left', bold: true, color: FAMILY_COLOR[f] } },
      cell(`${f2(e(lo, f).outer)}／${f2(e(lo, f).inner)}`), cell(`${f2(e(hi, f).outer)}／${f2(e(hi, f).inner)}`),
    ]),
  ], MARGIN_X + 9.0, 1.55, tw, [1.3, (tw - 1.3) / 2, (tw - 1.3) / 2], { fontSize: 10.5, rowH: 0.42 });
  addCard(slide, MARGIN_X, 5.3, CONTENT_W, 1.5, { fill: C.tint });
  addText(slide, `GPR（${hi} Shot）：外周 ${f2(e(hi, 'GPR').outer)} nm は内側 ${f2(e(hi, 'GPR').inner)} nm の ${f1(e(hi, 'GPR').outer / e(hi, 'GPR').inner)} 倍。外周の Mark は全体の ${pct(D.data.n_outer_marks / D.data.n_marks)}% だが、誤差の2乗和の多くを占める`,
    MARGIN_X + 0.3, 5.3, CONTENT_W - 0.6, 1.5, { fontSize: 14, valign: 'middle', bold: true });
}

// =====================================================================
// 24. 誤差マップ
// =====================================================================
{
  const slide = newContentSlide(SECTION.s3, '推定誤差のマップ ― 質的変数を入れると Mark ごとの縞が消える', [
    '1枚目のWaferで、X方向の推定誤差を地図にしました。上の段が10ショット、下の段が40ショットです。左端は真値で、丸が計測したマークです。',
    '質的変数を入れたGPRとGAMは、40ショットでは誤差がほぼ一様に小さくなります。',
    'TPSとXY5次は、マークごとのOffsetを表せないため、同じショットの中でマークごとに正負が入れ替わる、細かい縞が残ります。',
    '10ショットでは、どの手法も計測点から離れた外周で誤差が大きくなります。',
  ], { source: 'Wafer 0 の X 成分。灰色の点は計測した Mark（誤差は計算しない）。誤差 = 推定値 − 真値' });
  addFigure(slide, 'fig11_error_maps.png', MARGIN_X, 1.45, CONTENT_W, 5.45, '推定誤差マップ');
}

// =====================================================================
// 25. ばらつき
// =====================================================================
{
  const g = (n) => fixedAt('GPR', n);
  const slide = newContentSlide(SECTION.s3, 'Waferごとのばらつき ― 平均だけでなく悪い Wafer でも順序は同じ', [
    'Waferごとの誤差の分布です。箱は25から75パーセント点、線は中央値です。',
    `GPRの${mid}ショットでは、中央値が${f2(g(mid).RMSE_XY_median)}、90パーセント点が${f2(g(mid).RMSE_XY_q90)}ナノメートルでした。`,
    '面内傾向の大きさや形はWaferごとに違うので、誤差にも幅があります。',
    '系統の順序は、中央値でも上側の点でもほぼ同じで、悪いWaferだけで順序が入れ替わることはありませんでした。',
  ], { source: '系統ごとの最良の設定。外れ値は表示していない' });
  addFigure(slide, 'fig14_distribution.png', MARGIN_X, 1.45, CONTENT_W, 4.4, 'ばらつき');
  addStyledTable(slide, [
    tableHead(['GPR（最良の設定）', ...LEVELS.map((n) => `${n}`)]),
    [cell('中央値 [nm]', { align: 'left', bold: true }), ...LEVELS.map((n) => cell(f2(g(n).RMSE_XY_median)))],
    [cell('90%点 [nm]', { align: 'left', bold: true }), ...LEVELS.map((n) => cell(f2(g(n).RMSE_XY_q90)))],
  ], MARGIN_X, 5.95, CONTENT_W, [3.0, ...LEVELS.map(() => (CONTENT_W - 3.0) / LEVELS.length)], { fontSize: 11.5, rowH: 0.3 });
}

// =====================================================================
// 26. 計算時間
// =====================================================================
{
  const t = D.timing_ms;
  const slide = newContentSlide(SECTION.s3, '計算時間 ― GPR でも 1 Wafer 数十ミリ秒、Backfitting は数倍', [
    '1枚のWaferの推定にかかった時間です。XとYの合計で、Pythonでの計測値です。',
    `GPRは、${hi}ショットで、質的変数なしが${f1(t[String(hi)].GPR_none)}ミリ秒、同時推定が${f1(t[String(hi)].GPR_basis)}ミリ秒、Backfittingが${f1(t[String(hi)].GPR_backfit)}ミリ秒でした。`,
    'Backfittingはハイパーパラメータの推定を繰り返すので、同時推定の数倍かかります。同じ結果になるので、同時推定で十分です。',
    'XY5次、RT、TPSは線形の計算なので1ミリ秒未満です。',
    'いずれも、露光装置のスループットに影響する時間ではありません。ただし、並列で動かしたM1での値で、装置側の計算機とは異なります。',
  ], { source: 'Python 3.14、M1（6並列で実行中の計測値）。カーネル・説明変数を平均' });
  addFigure(slide, 'fig12_timing.png', MARGIN_X, 1.45, 8.2, 4.4, '計算時間', { align: 'left' });
  const groups = [['GPR_none', 'GPR（なし）'], ['GPR_basis', 'GPR（同時推定）'], ['GPR_backfit', 'GPR（Backfitting）'], ['TPS', 'TPS'], ['OK', 'Kriging'], ['UK', 'Universal Kriging'], ['GAM', 'GAM'], ['XY', 'XY5次'], ['RT', 'RT']];
  const rx = MARGIN_X + 8.45;
  const rw = SLIDE_W - MARGIN_X - rx;
  addStyledTable(slide, [
    tableHead(['手法', `${lo} Shot`, `${hi} Shot`]),
    ...groups.map(([key, name]) => [cell(name, { align: 'left', bold: true }), cell(f1(t[String(lo)][key])), cell(f1(t[String(hi)][key]))]),
  ], rx, 1.55, rw, [rw - 1.8, 0.9, 0.9], { fontSize: 11.5, rowH: 0.42 });
  addText(slide, '単位：ミリ秒（1 Wafer、X・Y の合計）', rx, 5.85, rw, 0.4, { fontSize: 10.5, color: C.muted });
}

// =====================================================================
// 27. 選び方のガイド
// =====================================================================
{
  const slide = newContentSlide(SECTION.s4, '選び方のガイド ― 計測Shot数と目的で選ぶ', [
    '結果をもとに、選び方をまとめます。',
    `基本はGPRで、カーネルは${gprFixed.variant}、説明変数はX, Yと半径、Scan方向とMark番号は基底関数として同時に推定する設定です。`,
    `計測ショットが${lo}ショット程度と少ない場合は、質的変数を入れると逆に悪くなるので、質的変数を入れないGPRかTPSを使います。境目のショット数は、実データで確認してください。`,
    'Backfittingは同時推定と同じ結果になるので、実装を簡単にするなら同時推定で十分です。',
    'Tは加えません。Krigingを使う場合は、バリオグラムの当てはめを最尤法に変えるか、GPRとして実装する方が良いです。',
  ]);
  const rows = [
    [`基本（${factorHelpsFrom} Shot 以上）`, `GPR ${gprFixed.variant}`, 'X, Y, 半径', '同時推定（基底関数）', `RMSE ${f2(familyRmse('GPR', mid))} nm（${mid} Shot）`],
    [`少ない（${lo} Shot 前後）`, 'GPR（質的変数なし）か TPS', 'X, Y, 半径', '入れない', `RMSE ${f2(gprMode(lo, 'none').rmse)} nm（${lo} Shot）`],
    ['実装を簡単にしたい', 'GAM（質的変数あり）', 'X, Y', '説明変数に追加', `RMSE ${f2(familyRmse('GAM', hi))} nm（${hi} Shot）`],
    ['線形の補正式が必要', 'XY5次（参考）', '－', '－', `RMSE ${f2(familyRmse('XY', hi))} nm（${hi} Shot）`],
  ];
  addStyledTable(slide, [
    tableHead(['状況', '手法', '説明変数', '質的変数（Scan・Mark）', '目安の精度']),
    ...rows.map((row, i) => row.map((t, j) => cell(t, { align: j < 2 ? 'left' : 'center', bold: j === 0, color: j === 1 && i === 0 ? C.gpr : C.ink }))),
  ], MARGIN_X, 1.55, CONTENT_W, [2.6, 2.6, 1.7, 2.4, CONTENT_W - 9.3], { fontSize: 13, rowH: 0.62 });
  const dont = [
    ['T（方位角）を加える', 'ARD では多くが無視され、等方カーネル・TPS・Kriging では悪化'],
    ['Backfitting を別に実装する', '同時推定と同じ解。計算は数倍'],
    ['Kriging（PyKrige 既定の当てはめ）', 'ナゲットを過大に推定して平らになりすぎる'],
  ];
  const w = (CONTENT_W - 2 * 0.3) / 3;
  addText(slide, '選ばなくてよいもの', MARGIN_X, 4.85, 6, 0.35, { fontSize: 14, bold: true, color: C.bad });
  dont.forEach(([title, desc], i) => {
    const x = MARGIN_X + i * (w + 0.3);
    addCard(slide, x, 5.3, w, 1.5, { fill: C.gray });
    addText(slide, title, x + 0.25, 5.42, w - 0.5, 0.45, { fontSize: 14, bold: true });
    addText(slide, desc, x + 0.25, 5.9, w - 0.5, 0.8, { fontSize: 12.5, color: C.muted });
  });
}

// =====================================================================
// 28. 前提と限界
// =====================================================================
{
  const slide = newContentSlide(SECTION.s4, '前提と限界 ― 模擬データの仮定と、次に確かめること', [
    'この評価の前提と限界です。',
    '数値はすべて模擬データによるもので、Zernikeの係数の大きさ、Mark OffsetとScan方向の差の大きさ、ノイズの広がり方は仮定した値です。実データでは成分の大きさの比が違い、手法の差も変わります。',
    'Scan方向の差は、マークによらない一定の差としました。Scan方向によってショットの形が変わる、つまりScan方向とMark番号の交互作用は含めていません。',
    '外周の欠けたショットや、Waferの端だけの急な変化も含めていません。',
    'サンプリング計画はXY5次を基準にしたI最適計画で、GPRにとって最適な配置ではありません。',
    '次に、実データでの検証、Scan方向とMark番号の交互作用、外周の重み付けを確かめる価値があります。',
  ]);
  const limits = [
    '模擬データの成分の大きさ（係数の減衰、Mark Offset、Scan 差、ノイズの広がり）は仮定値',
    'Scan 差は Mark によらない一定値。Scan 方向 × Mark 番号の交互作用は含めていない',
    '欠けた Shot、Wafer 端だけの急な変化、外れ値は含めていない',
    '計画は XY5 基準の I 最適（GPR にとっての最適配置ではない）',
    '評価は真値との比較。実データでは真値がなく、交差検証での評価が必要',
  ];
  const nexts = [
    '実データ（複数ロット）で同じ比較をし、成分の大きさを推定する',
    'Scan 方向 × Mark 番号の交互作用を質的変数に加える',
    '外周の計測誤差を重み（不均一なノイズ）として GPR に入れる',
    'GPR の予測分散を使ったサンプリング計画と比べる',
    'Kriging のバリオグラムを最尤法で当てはめた場合と比べる',
  ];
  const w = (CONTENT_W - 0.35) / 2;
  addCard(slide, MARGIN_X, 1.6, w, 5.2, { fill: C.gray });
  addText(slide, '前提と限界', MARGIN_X + 0.3, 1.75, w - 0.6, 0.45, { fontSize: 17, bold: true, color: C.bad });
  addBullets(slide, limits, MARGIN_X + 0.3, 2.35, w - 0.6, 4.3, { fontSize: 14, space: 14 });
  const rx = MARGIN_X + w + 0.35;
  addCard(slide, rx, 1.6, w, 5.2, { fill: C.tint });
  addText(slide, '次に確かめること', rx + 0.3, 1.75, w - 0.6, 0.45, { fontSize: 17, bold: true, color: C.indigo });
  nexts.forEach((text, i) => {
    const y = 2.35 + i * 0.86;
    addNode(slide, rx + 0.55, y + 0.3, 0.44, C.indigo, String(i + 1), { fontSize: 13 });
    addText(slide, text, rx + 0.95, y, w - 1.25, 0.66, { fontSize: 13.5, valign: 'middle' });
  });
}

// =====================================================================
// 29. まとめ
// =====================================================================
{
  const slide = pres.addSlide();
  pageNumber += 1;
  slide.background = { color: C.night };
  addText(slide, 'まとめ', 0.8, 0.55, 8, 0.7, { fontSize: 30, bold: true, color: C.white });
  const points = [
    `手法：${factorHelpsFrom} Shot 以上は GPR（${gprFixed.variant}）が最良（${mid} Shot ${f2(familyRmse('GPR', mid))}、${hi} Shot ${f2(familyRmse('GPR', hi))} nm）。GAM が続き、Kriging・XY5・RT は大きく劣る`,
    `説明変数：半径を足すと GPR で数%改善。T（方位角）を足すと悪化し、ARD では ${pct(D.ard_usage['XYRT|T'][String(hi)])}% で無視される`,
    `質的変数：Scan 方向・Mark 番号を入れると ${hi} Shot で ${signed(fxRel('basis-none', hi), 0)}%。${lo} Shot では ${signed(fxRel('basis-none', lo))}% と逆効果`,
    `Backfitting：同時推定と同じ解（差 0.01 nm 未満が ${pct(BV.share_within_001)}%）。同時推定で十分`,
    '指標：4指標で順位はほぼ同じ。調整済み R² は有効自由度の大きいモデルに厳しい',
  ];
  const colors = [C.gpr, C.tps, C.gam, C.backfit, C.ok];
  points.forEach((text, i) => {
    const y = 1.4 + i * 1.05;
    addNode(slide, 1.15, y + 0.45, 0.5, colors[i], String(i + 1), { fontSize: 16 });
    addText(slide, text, 1.65, y, 6.8, 0.95, { fontSize: 14, color: C.white, valign: 'middle' });
  });
  const rx = 8.75;
  const rw = SLIDE_W - 0.8 - rx;
  addCard(slide, rx, 1.5, rw, 5.0, { fill: C.motifDark });
  addText(slide, '推奨する設定', rx + 0.35, 1.7, rw - 0.7, 0.45, { fontSize: 17, bold: true, color: C.white });
  addBullets(slide, [
    `GPR（${gprFixed.variant}）`,
    '説明変数：X, Y, 半径',
    'Scan 方向・Mark 番号：基底関数で同時推定',
    `計測 Shot が ${lo} 前後なら、質的変数なしの GPR か TPS`,
    '実データで成分の大きさを確かめてから採用',
  ], rx + 0.35, 2.3, rw - 0.7, 4.0, { fontSize: 14, space: 12, color: C.onDarkSub });
  addText(slide, DECK_TITLE, 0.8, 7.02, 8, 0.3, { fontSize: 9.5, color: C.onDarkSub });
  addText(slide, String(pageNumber), SLIDE_W - 1.1, 7.02, 0.5, 0.3, { fontSize: 10, color: C.onDarkSub, align: 'right' });
  slide.addNotes([
    'まとめです。',
    `手法は、GPRが全ショット数で最も良く、カーネルは${gprFixed.variant}でした。GAMが続き、Kriging、XY5次、RTモデルは大きく劣りました。`,
    '説明変数は、半径を加えるとGPRで数パーセント良くなり、接線方向の位置Tを加えると悪くなりました。ARDカーネルではTが多くの場合に無視されました。',
    `Scan方向とMark番号を質的変数として入れると、${hi}ショットで誤差が${f0(-fxRel('basis-none', hi))}パーセント小さくなりました。${lo}ショットでは逆に悪くなるので、質的変数なしのGPRかTPSを使います。`,
    'Backfittingで追い込んでも、基底関数として同時に推定した場合と同じ解になるので、同時推定で十分です。',
    '4つの指標の順位はほぼ同じで、自由度調整済み決定係数は、有効自由度の大きいモデルに厳しい指標でした。',
    '実データで成分の大きさを確かめてから採用することをお勧めします。',
  ].join('\n'));
}

function f0(v) {
  return v.toFixed(0);
}

// =====================================================================
// 30. 参考文献
// =====================================================================
{
  const slide = newContentSlide(SECTION.s4, '参考文献', [
    '手法の定義と、ハイパーパラメータの決め方の出典です。',
    'GPRのカーネルと初期値はMATLABのfitrgpのドキュメント、バリオグラムの式と当てはめ方はPyKrigeのドキュメントに合わせました。',
  ]);
  const refs = [
    'MathWorks, "fitrgp — Fit a Gaussian process regression (GPR) model," MATLAB Documentation. https://www.mathworks.com/help/stats/fitrgp.html',
    'MathWorks, "Kernel (Covariance) Function Options," MATLAB Documentation. https://www.mathworks.com/help/stats/kernel-covariance-function-options.html',
    'C. E. Rasmussen, C. K. I. Williams, Gaussian Processes for Machine Learning, MIT Press (2006).',
    'PyKrige Documentation, "Variogram Models" / "OrdinaryKriging" / "UniversalKriging." https://geostat-framework.readthedocs.io/projects/pykrige/',
    'N. Cressie, Statistics for Spatial Data, Revised ed., Wiley (1993).',
    'G. Wahba, Spline Models for Observational Data, SIAM (1990) ／ P. Craven, G. Wahba, Numerische Mathematik 31, 377–403 (1979).',
    'S. N. Wood, Generalized Additive Models: An Introduction with R, 2nd ed., CRC Press (2017).',
    'S. N. Wood, "Fast stable restricted maximum likelihood and marginal likelihood estimation of semiparametric generalized linear models," JRSS B 73(1), 3–36 (2011).',
    'P. H. C. Eilers, B. D. Marx, "Flexible smoothing with B-splines and penalties," Statistical Science 11(2), 89–121 (1996).',
    'T. Hastie, R. Tibshirani, Generalized Additive Models, Chapman & Hall (1990) ／ A. Buja, T. Hastie, R. Tibshirani, Ann. Statist. 17(2), 453–510 (1989).',
    'A. C. Atkinson, A. N. Donev, R. D. Tobias, Optimum Experimental Designs, with SAS, Oxford University Press (2007).',
    'J. Menger ほか (ASML), US10495990B2 "Methods and apparatus for calculating substrate model parameters ..." (2019).',
  ];
  addBullets(slide, refs.map((r, i) => `[${i + 1}] ${r}`), MARGIN_X, 1.55, CONTENT_W, 4.75, { fontSize: 11.5, space: 4, bullet: false });
  addCard(slide, MARGIN_X, 6.25, CONTENT_W, 0.55, { fill: C.tint });
  addText(slide, '本資料の数値はすべて乱数で生成した模擬 Wafer による（実データ・社内データは使用していない）。計算コードは alignment-estimation-benchmark リポジトリ',
    MARGIN_X + 0.25, 6.25, CONTENT_W - 0.5, 0.55, { fontSize: 12, valign: 'middle' });
}

pres.writeFile({ fileName: OUTPUT_PATH }).then((file) => console.log(`書き出し: ${file}（${pageNumber} 枚）`));
