"""詳細機能一覧（HTML）を作る。

使い方：python3 build_html.py [出力 .html]
- 元データは同じフォルダの features.py（機能仕様書の PowerPoint と共通）。
- 1 つのファイルに CSS・JavaScript を入れる（メールに添付して、そのままブラウザで開けるように）。
出力は別名（.building.html）に書いてから置き換える。
"""
from __future__ import annotations

import html
import os
import sys
from pathlib import Path

from features import APP_FORMAL, APP_NAME, EDITION_LABELS, VERSION_NOTE, feature_count, numbered_sections

HERE = Path(__file__).resolve().parent
DEFAULT_OUTPUT = HERE.parent / f"{APP_NAME}_詳細機能一覧.html"
EDITION_CLASS = {"共通": "ed-both", "Pro": "ed-pro", "一部": "ed-part"}

CSS = """
:root{--navy:#22223b;--slate:#4a4e69;--muted:#6c6f7f;--line:#dadde6;--panel:#f3f4f8;--paper:#fff;--bg:#f6f7fa;
--coral:#e76f51;--teal:#2a9d8f;--purple:#8d6a9f;--gold:#9c7412;--teal-tint:#d8f0ed;--purple-tint:#ece3f1;--gold-tint:#fbf1d6;
--side:280px;color-scheme:light}
*{box-sizing:border-box}
html{scroll-behavior:smooth;scroll-padding-top:16px}
body{margin:0;background:var(--bg);color:var(--navy);font:14px/1.75 "BIZ UDGothic","Hiragino Kaku Gothic ProN","Yu Gothic UI","Yu Gothic",Meiryo,sans-serif}
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
td.impl{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px;color:var(--slate);min-width:170px;word-break:break-word}
col.c-id{width:66px}col.c-name{width:15%}col.c-desc{width:31%}col.c-ops{width:17%}col.c-out{width:14%}col.c-impl{width:15%}col.c-ed{width:86px}
.badge{display:inline-block;border-radius:999px;padding:1px 8px;font-size:11.5px;white-space:nowrap;font-weight:700}
.ed-both{background:var(--panel);color:var(--slate)}
.ed-pro{background:var(--purple-tint);color:#6a4a7c}
.ed-part{background:var(--gold-tint);color:#7a5a0c}
.intro-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;margin:10px 0 4px}
.card{background:var(--panel);border-radius:8px;padding:10px 14px}
.card h4{margin:0 0 4px;font-size:14px}
.card p{margin:0;font-size:13px}
.filters{position:sticky;top:0;z-index:5;display:flex;flex-wrap:wrap;gap:10px 18px;align-items:center;background:var(--bg);padding:10px 0 12px;margin:0 0 6px;border-bottom:1px solid var(--line)}
.filters label{font-size:13px;color:var(--slate);display:flex;gap:6px;align-items:center}
.filters input{width:300px;max-width:60vw;padding:6px 10px;border:1px solid var(--line);border-radius:6px;background:#fff}
.filters select{padding:5px 8px;border:1px solid var(--line);border-radius:6px;background:#fff}
.filters .result{font-size:12.5px;color:var(--muted)}
.hidden{display:none !important}
table.edition{min-width:0}
table.edition td,table.edition th{white-space:normal}
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
  const edition = document.getElementById('edition');
  const result = document.getElementById('result');
  const rows = Array.from(document.querySelectorAll('tr[data-ed]'));
  function apply(){
    const words = search.value.trim().toLowerCase().split(/\\s+/).filter(Boolean);
    const ed = edition.value;
    let shown = 0;
    rows.forEach(function(row){
      const text = row.textContent.toLowerCase();
      const okText = words.every(function(w){ return text.indexOf(w) >= 0; });
      const okEd = ed === 'all' || (ed === 'standard' ? row.dataset.ed !== 'Pro' : row.dataset.ed === ed);
      const ok = okText && okEd;
      row.classList.toggle('hidden', !ok);
      if (ok) { shown++; }
    });
    document.querySelectorAll('.group').forEach(function(group){
      group.classList.toggle('hidden', !group.querySelector('tr[data-ed]:not(.hidden)'));
    });
    result.textContent = shown + ' / ' + rows.length + ' 件を表示';
  }
  search.addEventListener('input', apply);
  edition.addEventListener('change', apply);
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


def edition_badge(edition: str) -> str:
    return f'<span class="badge {EDITION_CLASS[edition]}">{esc(EDITION_LABELS[edition])}</span>'


def build() -> str:
    sections = numbered_sections()
    total = feature_count()
    toc = ['<li><a href="#guide"><span>この一覧の見方</span></a></li>',
           '<li><a href="#editions"><span>通常版と Pro 版の違い</span></a></li>']
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
                         '<col class="c-out"><col class="c-impl"><col class="c-ed"></colgroup>'
                         '<thead><tr><th scope="col">ID</th><th scope="col">機能</th><th scope="col">内容</th>'
                         '<th scope="col">操作・入力</th><th scope="col">結果・出力</th><th scope="col">主な実装</th>'
                         '<th scope="col">版</th></tr></thead><tbody>')
            for row in rows:
                parts.append(f'<tr data-ed="{esc(row["ed"])}"><td class="id">{row["id"]}</td>'
                             f'<td class="name">{esc(row["name"])}</td><td>{esc(row["desc"])}</td>'
                             f'<td>{esc(row["ops"])}</td><td>{esc(row["out"])}</td>'
                             f'<td class="impl">{esc(row["impl"])}</td><td>{edition_badge(row["ed"])}</td></tr>')
            parts.append('</tbody></table></div></div>')
        parts.append('</section>')
        body.append("".join(parts))

    pro_only = sum(1 for s in sections for _, rows in s["groups"] for r in rows if r["ed"] == "Pro")
    partial = sum(1 for s in sections for _, rows in s["groups"] for r in rows if r["ed"] == "一部")
    guide = f"""
<section class="chapter" id="guide" aria-labelledby="guide-h">
<h2 class="chapter-title" id="guide-h">この一覧の見方</h2>
<p class="summary">{esc(APP_NAME)}（{esc(APP_FORMAL)}）の機能を、画面のタブごとに 1 行ずつ並べた一覧です。
全 {total} 機能。機能仕様書（PowerPoint）の「機能の詳細」と同じ ID を使います。</p>
<div class="intro-grid">
<div class="card"><h4>列の意味</h4><p>「操作・入力」は画面の欄・ボタンの名前、「結果・出力」は画面に出るもの・書き出すファイル、
「主な実装」は処理を受け持つ関数（+alignest の関数は名前だけ、+appui の画面の関数も名前だけ）です。</p></div>
<div class="card"><h4>版の印</h4><p>{edition_badge("共通")} どちらの版でも使える　{edition_badge("Pro")} Pro 版だけ（{pro_only} 機能）
　{edition_badge("一部")} 通常版は選択肢を絞る（{partial} 機能）</p></div>
<div class="card"><h4>探し方</h4><p>上の検索欄に言葉（空白で区切ると全部を含む行）を入れるか、版で絞り込みます。左の目次で章へ移動できます。</p></div>
</div>
</section>
<section class="chapter" id="editions" aria-labelledby="editions-h">
<h2 class="chapter-title" id="editions-h">通常版と Pro 版の違い</h2>
<p class="summary">同じプログラムから 2 つの版を作れます。違うのは「2. 面内推定の設定」の 3 つの設定だけで、ほかのタブ・機能は同じです。</p>
<div class="table-wrap"><table class="edition"><thead><tr><th scope="col">設定</th><th scope="col">通常版</th><th scope="col">Pro 版</th></tr></thead><tbody>
<tr><td class="name">比べる手法</td><td>GPR（カーネル・質的変数の扱いはすべて）・TPS・XY 多項式</td><td>すべて（RBF・Kriging・Universal Kriging・GAM・RT モデル・Fringe Zernike も）</td></tr>
<tr><td class="name">計測点の選び方</td><td>Shot 単位の I 最適・ランダム</td><td>すべて（D 最適・Sobol 列・ポアソンディスク・Excel 取込・Mark 単位も）</td></tr>
<tr><td class="name">Overlay 補正の成分</td><td>組み込みの式（Wafer 成分の次数・1 次）</td><td>「式を入力」も</td></tr>
<tr><td class="name">起動</td><td>runAlignmentEstimationAppStandard（窓の名前に「（通常版）」）</td><td>runAlignmentEstimationApp</td></tr>
</tbody></table></div>
</section>
"""
    return f"""<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(APP_NAME)} 詳細機能一覧</title>
<style>{CSS}</style>
</head>
<body>
<a class="skip" href="#content">本文へ移動</a>
<header class="top" id="page-top" tabindex="-1">
<p class="kicker">機能仕様書の付録 ｜ {esc(VERSION_NOTE)}</p>
<h1>{esc(APP_NAME)}（LUCAS）詳細機能一覧</h1>
<p>MATLAB アプリの全 {total} 機能を、画面のタブごとに、内容・操作・出力・実装・版で整理</p>
</header>
<div class="layout">
<nav class="toc" aria-label="目次"><h2>目次</h2><ol>{''.join(toc)}</ol></nav>
<main id="content">
<div class="filters" role="search">
<label for="search">検索 <input id="search" type="search" placeholder="例：VIF、Excel、GPR 分散"></label>
<label for="edition">版 <select id="edition">
<option value="all">すべて</option><option value="standard">通常版で使える機能</option>
<option value="Pro">Pro 版だけの機能</option><option value="一部">通常版は一部の機能</option></select></label>
<span class="result" id="result" aria-live="polite"></span>
</div>
{guide}
{''.join(body)}
<footer>元データ：docs/specification/_src/features.py（README とコードに合わせて作成）。作り直し：python3 build_html.py</footer>
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
    print(f"書き出しました：{output}（{feature_count()} 機能）")


if __name__ == "__main__":
    main()
