// 説明資料（pptxgenjs）の共通部品。見た目は「技術レポートPowerPoint」テンプレート（濃紺の表紙とまとめ、白地の本文）に合わせる。
// 使い方：const { createDeckKit } = require('../deck_common/deck_kit');
//         const kit = createDeckKit({ pres, colors, deckTitle, formulaDir, figureDir });
// colors には ink・muted・indigo・white・tint・gray・grid・line を含める。
// 文字・図形・数式・図・表・本文スライドの枠を作る関数と、ページ番号（nextPage・pageCount）を返す。

const path = require('path');
const fs = require('fs');

const SLIDE_W = 13.333;
const SLIDE_H = 7.5;
const MARGIN_X = 0.6;
const CONTENT_W = SLIDE_W - MARGIN_X * 2;
const FONT = 'BIZ UDGothic';

function createDeckKit({ pres, colors, deckTitle, formulaDir, figureDir }) {
  const C = colors;
  const DECK_TITLE = deckTitle;
  const formulaSizes = JSON.parse(fs.readFileSync(path.join(formulaDir, 'formulas.json'), 'utf8'));
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
    slide.addImage({ path: path.join(formulaDir, formulaSizes[key].file), x, y, w: size.w, h: size.h, altText: alt || key });
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
    const file = path.join(figureDir, name);
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

  function nextPage() {
    pageNumber += 1;
    return pageNumber;
  }

  function pageCount() {
    return pageNumber;
  }

  return {
    parseRich, toRuns, addText, paragraphs, addBullets, withBreaks,
    addCard, addLine, addNode, formulaSize, addFormula, addFormulaCard, pngSize, addFigure,
    addNumberedCard, addStat, addChip, tableHead, cell, addStyledTable,
    newContentSlide, chartBase, nextPage, pageCount,
  };
}

module.exports = { createDeckKit, SLIDE_W, SLIDE_H, MARGIN_X, CONTENT_W, FONT };
