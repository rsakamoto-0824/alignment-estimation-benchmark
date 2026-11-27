"""詳細機能一覧（HTML。通常版の機能だけ）を作る。

使い方：python3 build_html.py [出力 .html]
- 元データは同じフォルダの features.py（機能仕様書の PowerPoint と共通）と formulas.py（計算式の章）。
- 通常版で使える機能だけを出す（Pro 版だけの機能は出さず、通常版で選択肢を絞る機能は通常版の内容を出す）。
- 1 つのファイルに CSS・JavaScript を入れる（メールに添付して、そのままブラウザで開けるように）。
出力は別名（.building.html）に書いてから置き換える。
"""
from __future__ import annotations

import html
import os
import sys
from pathlib import Path

from features import APP_FORMAL, APP_NAME, VERSION_NOTE, numbered_sections
from formulas import FORMULA_SECTIONS

HERE = Path(__file__).resolve().parent
DEFAULT_OUTPUT = HERE.parent / f"{APP_NAME}_詳細機能一覧.html"
UI_FONTS = '"Meiryo UI", "Hiragino Sans", "Hiragino Kaku Gothic ProN", "Yu Gothic UI", "Yu Gothic", Meiryo, sans-serif'

CSS = """
:root{--navy:#22223b;--slate:#4a4e69;--muted:#6c6f7f;--line:#dadde6;--panel:#f3f4f8;--paper:#fff;--bg:#f6f7fa;
--coral:#e76f51;--teal:#2a9d8f;--purple:#8d6a9f;--gold:#9c7412;--teal-tint:#d8f0ed;--purple-tint:#ece3f1;--gold-tint:#fbf1d6;
--side:280px;color-scheme:light}
*{box-sizing:border-box}
html{scroll-behavior:smooth;scroll-padding-top:16px}
body{margin:0;background:var(--bg);color:var(--navy);font-family:UIFONTS;font-size:14.5px;line-height:1.8;letter-spacing:.02em}
a{color:#2f5d8a;text-underline-offset:3px}
a:focus-visible,button:focus-visible,input:focus-visible,select:focus-visible,summary:focus-visible{outline:3px solid var(--gold);outline-offset:2px}
.skip{position:absolute;left:-999px;top:0;background:var(--navy);color:#fff;padding:8px 12px;z-index:10}
.skip:focus{left:8px;top:8px}
header.top{background:var(--navy);color:#fff;padding:14px 28px 12px}
header.top .kicker{font-size:12px;color:#a9acc6;margin:0}
header.top h1{font-size:22px;margin:2px 0 4px;line-height:1.4}
header.top p{margin:0;font-size:13px;color:#d9dbea}
.layout{display:grid;grid-template-columns:var(--side) minmax(0,1fr);align-items:start}
nav.toc{position:sticky;top:0;max-height:100vh;overflow:auto;padding:18px 14px 24px 20px;border-right:1px solid var(--line);background:var(--paper)}
nav.toc h2{font-size:13px;color:var(--muted);margin:0 0 8px;letter-spacing:.04em}
nav.toc ol{list-style:none;margin:0;padding:0}
nav.toc li{margin:0}
nav.toc a{display:flex;justify-content:space-between;gap:8px;padding:5px 8px;border-radius:6px;color:var(--navy);text-decoration:none;font-size:13.5px}
nav.toc a:hover{background:var(--panel)}
nav.toc a.active{background:var(--teal-tint);font-weight:700}
nav.toc .count{color:var(--muted);font-size:12px;font-weight:400}
nav.toc ol ol a{padding-left:20px;font-size:12.5px;color:var(--slate)}
main{padding:22px 32px 80px;min-width:0}
section.chapter{background:var(--paper);border:1px solid var(--line);border-radius:10px;padding:18px 22px 20px;margin:0 0 20px}
h2.chapter-title{font-size:20px;margin:0 0 4px;line-height:1.45}
.chapter-meta{color:var(--muted);font-size:12.5px;margin:0 0 8px}
.summary{margin:0 0 10px}
h3{font-size:15.5px;margin:18px 0 6px;color:var(--slate)}
.table-wrap{overflow-x:auto;border:1px solid var(--line);border-radius:8px}
table{border-collapse:collapse;width:100%;min-width:980px;font-size:13px;background:var(--paper)}
th,td{border-bottom:1px solid var(--line);padding:7px 9px;vertical-align:top;text-align:left}
th{background:var(--slate);color:#fff;font-weight:700;position:sticky;top:0;white-space:nowrap}
tr:last-child td{border-bottom:0}
td.id{white-space:nowrap;color:var(--muted);font-variant-numeric:tabular-nums}
td.name{font-weight:700;min-width:150px}
td.impl{font-family:Consolas,Menlo,"Courier New",monospace;font-size:12.5px;color:var(--slate);min-width:170px;word-break:break-word}
col.c-id{width:66px}col.c-name{width:16%}col.c-desc{width:34%}col.c-ops{width:18%}col.c-out{width:15%}col.c-impl{width:17%}
.formula{white-space:pre-wrap;background:var(--panel);border-radius:8px;padding:10px 14px;margin:8px 0 10px;font-size:14px;line-height:1.9;overflow-x:auto}
.formula sub,.formula sup{font-size:.72em}
table.plain{min-width:0}
td.math{font-family:UIFONTS;white-space:normal}
code{font-family:Consolas,Menlo,"Courier New",monospace;font-size:.92em;background:var(--panel);padding:0 4px;border-radius:4px}
.intro-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;margin:10px 0 4px}
.card{background:var(--panel);border-radius:8px;padding:10px 14px}
.card h4{margin:0 0 4px;font-size:14px}
.card p{margin:0;font-size:13px}
.filters{position:sticky;top:0;z-index:5;display:flex;flex-wrap:wrap;gap:10px 18px;align-items:center;background:var(--bg);padding:10px 0 12px;margin:0 0 6px;border-bottom:1px solid var(--line)}
.filters label{font-size:13px;color:var(--slate);display:flex;gap:6px;align-items:center}
.filters input{width:300px;max-width:60vw;padding:6px 10px;border:1px solid var(--line);border-radius:6px;background:#fff}
.filters .result{font-size:12.5px;color:var(--muted)}
.hidden{display:none !important}
.to-top{position:fixed;right:22px;bottom:22px;width:46px;height:46px;border-radius:50%;border:0;background:var(--navy);color:#fff;font-size:20px;box-shadow:0 2px 8px rgba(34,34,59,.3);cursor:pointer;opacity:0;pointer-events:none;transition:opacity .2s}
.to-top.show{opacity:1;pointer-events:auto}
footer{color:var(--muted);font-size:12px;margin-top:24px}
@media (max-width:900px){
 .layout{grid-template-columns:1fr}
 nav.toc{position:static;max-height:none;border-right:0;border-bottom:1px solid var(--line)}
 nav.toc ol ol{display:none}
 main{padding:16px 16px 80px}
 .intro-grid{grid-template-columns:1fr}
 .filters{position:static}
 .to-top{right:14px;bottom:14px}
}
@media print{nav.toc,.filters,.to-top{display:none}.layout{display:block}th{position:static}section.chapter{break-inside:auto}}
"""

SCRIPT = """
(function(){
  const search = document.getElementById('search');
  const result = document.getElementById('result');
  const rows = Array.from(document.querySelectorAll('tr[data-feature]'));
  function apply(){
    const words = search.value.trim().toLowerCase().split(/\\s+/).filter(Boolean);
    let shown = 0;
    rows.forEach(function(row){
      const text = row.textContent.toLowerCase();
      const ok = words.every(function(w){ return text.indexOf(w) >= 0; });
      row.classList.toggle('hidden', !ok);
      if (ok) { shown++; }
    });
    document.querySelectorAll('.group').forEach(function(group){
      group.classList.toggle('hidden', !group.querySelector('tr[data-feature]:not(.hidden)'));
    });
    result.textContent = shown + ' / ' + rows.length + ' 件を表示';
  }
  search.addEventListener('input', apply);
  apply();
  const top = document.getElementById('to-top');
  window.addEventListener('scroll', function(){ top.classList.toggle('show', window.scrollY > 400); }, {passive:true});
  top.addEventListener('click', function(){ window.scrollTo({top:0, behavior:'smooth'}); document.getElementById('page-top').focus({preventScroll:true}); });
  const links = Array.from(document.querySelectorAll('nav.toc > ol > li > a'));
  const targets = links.map(function(a){ return document.querySelector(a.getAttribute('href')); });
  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(function(entries){
      entries.forEach(function(entry){
        if (entry.isIntersecting) {
          links.forEach(function(a){ a.classList.toggle('active', a.getAttribute('href') === '#' + entry.target.id); });
        }
      });
    }, {rootMargin:'0px 0px -70% 0px'});
    targets.forEach(function(t){ if (t) { observer.observe(t); } });
  }
})();
"""


def esc(value: str) -> str:
    return html.escape(value, quote=True)


def standard_sections():
    """通常版の機能だけ（Pro 版だけの機能を除き、通常版で選択肢を絞る機能は通常版の内容）。ID は機能仕様書と同じ"""
    result = []
    for section in numbered_sections():
        groups = []
        for title, rows in section["groups"]:
            kept = [dict(row, desc=row["std_desc"], ops=row["std_ops"]) for row in rows if row["ed"] != "Pro"]
            if kept:
                groups.append((title, kept))
        result.append({**section, "groups": groups, "count": sum(len(rows) for _, rows in groups)})
    return result


def build() -> str:
    sections = standard_sections()
    total = sum(section["count"] for section in sections)
    toc = ['<li><a href="#guide"><span>この一覧の見方</span></a></li>']
    body = []
    for section in sections:
        anchor = f"tab-{section['key']}"
        sub = "".join(f'<li><a href="#{anchor}-{index}">{esc(title)}</a></li>'
                      for index, (title, _) in enumerate(section["groups"], start=1))
        toc.append(f'<li><a href="#{anchor}"><span>{esc(section["title"])}</span>'
                   f'<span class="count">{section["count"]}</span></a><ol>{sub}</ol></li>')
        parts = [f'<section class="chapter" id="{anchor}" aria-labelledby="{anchor}-h">',
                 f'<h2 class="chapter-title" id="{anchor}-h">{esc(section["title"])}</h2>',
                 f'<p class="chapter-meta">画面のファイル：+appui/{esc(section["file"])}　｜　{section["count"]} 機能</p>',
                 f'<p class="summary">{esc(section["summary"])}</p>']
        for index, (title, rows) in enumerate(section["groups"], start=1):
            parts.append(f'<div class="group"><h3 id="{anchor}-{index}">{esc(title)}</h3><div class="table-wrap"><table>'
                         '<colgroup><col class="c-id"><col class="c-name"><col class="c-desc"><col class="c-ops">'
                         '<col class="c-out"><col class="c-impl"></colgroup>'
                         '<thead><tr><th scope="col">ID</th><th scope="col">機能</th><th scope="col">内容</th>'
                         '<th scope="col">操作・入力</th><th scope="col">結果・出力</th><th scope="col">主な実装</th>'
                         '</tr></thead><tbody>')
            for row in rows:
                parts.append(f'<tr data-feature="1"><td class="id">{row["id"]}</td>'
                             f'<td class="name">{esc(row["name"])}</td><td>{esc(row["desc"])}</td>'
                             f'<td>{esc(row["ops"])}</td><td>{esc(row["out"])}</td>'
                             f'<td class="impl">{esc(row["impl"])}</td></tr>')
            parts.append('</tbody></table></div></div>')
        parts.append('</section>')
        body.append("".join(parts))

    formula_toc = "".join(f'<li><a href="#{fid}">{esc(title)}</a></li>' for fid, title, _ in FORMULA_SECTIONS)
    toc.append(f'<li><a href="#formulas"><span>計算式</span><span class="count">{len(FORMULA_SECTIONS)}</span></a>'
               f'<ol>{formula_toc}</ol></li>')
    formula_parts = ['<section class="chapter" id="formulas" aria-labelledby="formulas-h">',
                     '<h2 class="chapter-title" id="formulas-h">計算式</h2>',
                     '<p class="summary">ばらつき分解・補正の式など、結果の数を求める式です（アプリのヘルプの技術編と同じ）。</p>']
    for fid, title, html_body in FORMULA_SECTIONS:
        formula_parts.append(f'<h3 id="{fid}">{esc(title)}</h3>{html_body}')
    formula_parts.append('</section>')
    body.append("".join(formula_parts))
    guide = f"""
<section class="chapter" id="guide" aria-labelledby="guide-h">
<h2 class="chapter-title" id="guide-h">この一覧の見方</h2>
<p class="summary">{esc(APP_NAME)}（{esc(APP_FORMAL)}）の<strong>通常版</strong>で使える機能を、画面のタブごとに 1 行ずつ並べた一覧です。
全 {total} 機能。ID は機能仕様書（PowerPoint）の「機能の詳細」と同じです（Pro 版だけの機能は載せないので、番号が飛ぶことがあります）。
最後の章に、ばらつき分解・補正の式などの計算式をまとめています。</p>
<div class="intro-grid">
<div class="card"><h4>列の意味</h4><p>「操作・入力」は画面の欄・ボタンの名前、「結果・出力」は画面に出るもの・書き出すファイル、
「主な実装」は処理を受け持つ関数の名前（保守する人向け）です。</p></div>
<div class="card"><h4>通常版</h4><p>起動は runAlignmentEstimationAppStandard（窓の名前に「（通常版）」）。RT モデル・D 最適などの計測点の選び方・
Overlay の式の入力・ダークモード・凡例の位置などは Pro 版の機能です。</p></div>
<div class="card"><h4>探し方</h4><p>上の検索欄に言葉を入れると、その言葉を含む行だけを出します（空白で区切ると全部を含む行）。左の目次で章へ移動できます。</p></div>
</div>
</section>
"""
    return f"""<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(APP_NAME)} 詳細機能一覧（通常版）</title>
<style>{CSS.replace("UIFONTS", UI_FONTS)}</style>
</head>
<body>
<a class="skip" href="#content">本文へ移動</a>
<header class="top" id="page-top" tabindex="-1">
<p class="kicker">機能仕様書の付録 ｜ {esc(VERSION_NOTE)}</p>
<h1>{esc(APP_NAME)}（LUCAS）詳細機能一覧（通常版）</h1>
<p>通常版の全 {total} 機能を、画面のタブごとに、内容・操作・出力・実装で整理し、計算式をまとめる</p>
</header>
<div class="layout">
<nav class="toc" aria-label="目次"><h2>目次</h2><ol>{''.join(toc)}</ol></nav>
<main id="content">
<div class="filters" role="search">
<label for="search">検索 <input id="search" type="search" placeholder="例：VIF、Excel、残留"></label>
<span class="result" id="result" aria-live="polite"></span>
</div>
{guide}
{''.join(body)}
<footer>元データ：docs/specification/_src/features.py・formulas.py（README・ヘルプ・コードに合わせて作成）。作り直し：python3 build_html.py</footer>
</main>
</div>
<button class="to-top" id="to-top" type="button" aria-label="ページの先頭へ戻る">↑</button>
<script>{SCRIPT}</script>
</body>
</html>
"""


def main():
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUTPUT
    building = output.with_suffix(".building.html")
    building.write_text(build(), encoding="utf-8")
    os.replace(building, output)
    total = sum(section["count"] for section in standard_sections())
    print(f"書き出しました：{output}（通常版 {total} 機能）")


if __name__ == "__main__":
    main()
