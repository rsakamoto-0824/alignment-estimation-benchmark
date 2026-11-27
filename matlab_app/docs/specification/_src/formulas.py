"""詳細機能一覧（HTML）の「計算式」の章（ばらつき分解・補正の式など）。

式はアプリのヘルプ（help/help.html の技術編）とコード（+alignest）に合わせる。メーカーの補正の式（Canon・Nikon）は
Overlay 計測ルールの式のまま（項・係数番号・符号を変えない。alignest.overlayTerms と同じ）。
各要素は (id, 見出し, HTML の本文)。
"""
from __future__ import annotations

FORMULA_SECTIONS = [
    ("formula-variance", "ばらつき分解（Lot・Wafer・Shot 間）", """
<p>「1. データ読込」の「ばらつき分解」（分け方「Lot・Wafer・Shot 間」）と、「3. 結果一覧」の「補正残差のばらつき分解」の計算です。
点（Mark）ごとの値の分散を、入れ子の段（上から Lot → Wafer → Shot）の分散成分に分けます（入れ子の分散分析・モーメント法。
<code>alignest.varianceDecomposition</code>）。</p>
<div class="formula">値 = 全体の平均 + Lot の効果 + Wafer の効果 + Shot の効果 + その他
全体の分散 σ<sup>2</sup> = σ<sub>Lot</sub><sup>2</sup> + σ<sub>Wafer</sub><sup>2</sup> + σ<sub>Shot</sub><sup>2</sup> + σ<sub>その他</sub><sup>2</sup>　（分散の加法性）
段 k の平方和 SS<sub>k</sub> = Σ<sub>段 k の組 g</sub> n<sub>g</sub> (g の平均 − g の上の段の組の平均)<sup>2</sup>、　その他の平方和 = Σ<sub>点</sub> (値 − Shot の平均)<sup>2</sup>
平均平方 MS<sub>k</sub> = SS<sub>k</sub> / 自由度<sub>k</sub>　（自由度 = 段 k の組の数 − 上の段の組の数、その他は 点の数 − Shot の数）
E[MS<sub>k</sub>] = σ<sub>その他</sub><sup>2</sup> + Σ<sub>j ≥ k</sub> c<sub>kj</sub> σ<sub>j</sub><sup>2</sup>、
　c<sub>kj</sub> = [Σ<sub>段 k の組 y</sub> Σ<sub>y の中の段 j の組 x</sub> n<sub>x</sub><sup>2</sup>/n<sub>y</sub> − (同じ和を段 k − 1 の組で)] / 自由度<sub>k</sub>
σ<sub>その他</sub><sup>2</sup> = MS<sub>その他</sub>、　下の段から σ<sub>k</sub><sup>2</sup> = (MS<sub>k</sub> − σ<sub>その他</sub><sup>2</sup> − Σ<sub>j &gt; k</sub> c<sub>kj</sub> σ<sub>j</sub><sup>2</sup>) / c<sub>kk</sub>　（負なら 0）
段の 3σ = 3√σ<sub>k</sub><sup>2</sup>、　全体の 3σ = 3√σ<sup>2</sup>
3σ の配分 = 全体の 3σ × σ<sub>k</sub><sup>2</sup> / σ<sup>2</sup>　（足すと全体の 3σ）、　割合 = σ<sub>k</sub><sup>2</sup> / σ<sup>2</sup> × 100 [%]</div>
<ul>
<li>下の段は上の段の中で分けます（Wafer はその Lot の中、Shot はその Wafer の中）。平均平方の期待値の式で下の段のばらつきを差し引くので、
平方和を点の数で割っただけの値より上の段が小さくなります。釣り合ったデータでは σ<sub>Shot</sub><sup>2</sup> = (MS<sub>Shot</sub> − MS<sub>その他</sub>) / n などの、よく知られた式と同じです。</li>
<li>3σ は足しても全体の 3σ になりません（全体の 3σ<sup>2</sup> = 段の 3σ<sup>2</sup> の和）。そのため図は「3σ の配分」を積み上げます。</li>
<li>その他 = Shot の中のばらつき（Mark ごとの違いと計測のばらつき）。Lot 間は Lot が 2 つ以上あるときだけ分けます。</li>
<li>「絞り込み」で選んだ列（装置・ロット・Operation・ファイルのその他の列）の値の点だけで分けます。</li>
</ul>"""),
    ("formula-components", "ばらつき分解（成分）", """
<p>「1. データ読込」の「ばらつき分解」の分け方「成分」です。Wafer ごと・軸ごとに、次の 2 段の最小二乗で回帰係数と残留を求めます
（座標は mm。<code>alignest.componentCoefficients</code>）。</p>
<div class="formula">① Wafer の成分：Shot s ごとの n<sub>s</sub> 点の平均 m<sub>s</sub> を、Shot 中心 (X<sub>s</sub>, Y<sub>s</sub>) に n<sub>s</sub> の重みで当てはめる
　X：m<sub>s</sub> = 全体 Shift + Wafer 倍率 × X<sub>s</sub> + Wafer 回転 × Y<sub>s</sub>
　Y：m<sub>s</sub> = 全体 Shift + Wafer 倍率 × Y<sub>s</sub> + Wafer 回転 × X<sub>s</sub>
　Wafer 成分の残留 = 3 × std<sub>点 i</sub>( e<sub>s(i)</sub> )、　e<sub>s</sub> = m<sub>s</sub> − (当てはめた値)　（Wafer レベルの回帰残差。点 i にはその Shot の残差を数える）
② Shot 共通の成分：点 i の値 v<sub>i</sub> からその Shot の平均を除いた値を、Shot 内の座標から Shot ごとの平均を引いた (x̃<sub>i</sub>, ỹ<sub>i</sub>) に当てはめる
　X：v<sub>i</sub> − m<sub>s</sub> = Shot 倍率 × x̃<sub>i</sub> + Shot 回転 × ỹ<sub>i</sub>
　Y：v<sub>i</sub> − m<sub>s</sub> = Shot 倍率 × ỹ<sub>i</sub> + Shot 回転 × x̃<sub>i</sub>
　Shot 共通成分の残留 = 3 × std<sub>点 i</sub>( (v<sub>i</sub> − m<sub>s</sub>) − (当てはめた値) )　（Shot レベルの回帰残差）</div>
<ul>
<li>全体 Shift と残留の単位は nm、倍率・回転は nm/mm（= ppm。回転は µrad）。std は標本標準偏差（n − 1 で割る）。</li>
<li>回帰に切片があるので残差の平均は 0 になり、残留の 3σ は |平均| + 3σ と同じ大きさです。</li>
<li>点・Shot が足りず決まらない係数（例：Shot が 2 つ以下の Wafer の Wafer 倍率・回転）と、その段の残留は空欄です。</li>
</ul>"""),
    ("formula-overlay", "Overlay 補正（基準の補正）", """
<p>「2. 面内推定の設定」の「評価・Overlay 補正」で選ぶ補正モデルです（<code>alignest.overlayDesign</code>）。「5. 未知の座標の推定」の
補正の比較では、これを<strong>基準の補正</strong>にします。</p>
<div class="formula">補正量(Mark) = Wafer 成分(X, Y) + Shot 共通成分(x, y) + Shot ごとの成分<sub>Shot</sub>(x, y)
X・Y：Shot 中心の座標（Wafer 半径で割る）、x・y：Shot 内の Mark の座標（markXmm・markYmm）
Wafer 成分 N 次　dx = Σ<sub>i+j≤N</sub> a<sub>ij</sub> X<sup>i</sup>Y<sup>j</sup>、　dy = Σ<sub>i+j≤N</sub> b<sub>ij</sub> X<sup>i</sup>Y<sup>j</sup>　（1次は並進・倍率・回転・直交度）
Shot 共通成分 1次　dx = k1 + k3·x + k5·y、　dy = k2 + k4·y + k6·x　（全 Shot で同じ係数）
Shot ごとの成分 1次　dx = k1<sub>Shot</sub> + k3<sub>Shot</sub>·x + k5<sub>Shot</sub>·y、　dy = k2<sub>Shot</sub> + k4<sub>Shot</sub>·y + k6<sub>Shot</sub>·x</div>
<p>dx（X 成分）・dy（Y 成分）を別々に最小二乗で当てはめます。成分どうしで重なる項（例：Wafer 成分の定数と k1）があっても、当てはめた補正量は
1 つに決まります（列空間への射影）。評価のしかた：</p>
<div class="formula">A：全 Mark の計測値、　E：学習点は計測値・評価点は推定値
実測値で補正した残差　R<sub>A</sub> = A − 補正量(A)
推定値で補正した残差　R<sub>E</sub> = A − 補正量(E)
推定による変化　　　　D = R<sub>E</sub> − R<sub>A</sub> = 補正量(A) − 補正量(E)
代表値　|平均| + 3σ（X・Y 別。σ は不偏標準偏差）、　推定による増加 = (R<sub>E</sub> の値) − (R<sub>A</sub> の値)</div>"""),
    ("formula-shot-formulas", "Shot 内の補正式（1 次・2 次・ASML・Canon・Nikon・カスタム）", """
<p>「6. Shot高次補正」「7. Mark配置最適化」と、「5. 未知の座標の推定」の補正のモデルの Shot 共通成分で使う式です（x・y は Shot 内の座標）。
Canon・Nikon は Overlay 計測ルールの式のまま（項・係数番号・変数・符号は変えない）、ASML は k1〜k19 のすべての項です。</p>
<div class="table-wrap"><table class="plain">
<thead><tr><th scope="col">式</th><th scope="col">dx</th><th scope="col">dy</th></tr></thead><tbody>
<tr><td class="name">1次</td><td class="math">k1 + k3·x + k5·y</td><td class="math">k2 + k4·y + k6·x</td></tr>
<tr><td class="name">2次</td><td class="math">k1 + k3·x + k5·y + k7·x² + k9·x·y + k11·y²</td><td class="math">k2 + k4·y + k6·x + k8·y² + k10·x·y + k12·x²</td></tr>
<tr><td class="name">ASML</td><td class="math">k1 + k3·x + k5·y + k7·x² + k9·x·y + k11·y² + k13·x³ + k15·x²·y + k17·x·y² + k19·y³</td><td class="math">k2 + k4·y + k6·x + k8·y² + k10·x·y + k12·x² + k14·y³ + k16·x·y² + k18·x²·y</td></tr>
<tr><td class="name">Canon</td><td class="math">k1 + k3·x + k5·y + k9·x·y + k11·y² + k17·x·y² + k19·y³ + k27·x·y³</td><td class="math">k2 + k4·y + k6·x + k8·y² + k10·x·y + k14·y³ + k16·x·y² + k24·x·y³</td></tr>
<tr><td class="name">Nikon</td><td class="math">k1 + k3·x + k5·y + k7·x² + k9·x·y + k11·y² + k13·x³ + k17·x·y² + k19·y³ + k29·y⁴ + k41·y⁵ + k55·y⁶</td><td class="math">k2 + k4·y + k6·x + k8·y² + k10·x·y + k12·x² + k14·y³ + k16·x·y² + k18·x²·y + k22·y⁴ + k24·x·y³ + k32·y⁵ + k34·x·y⁴ + k44·y⁶ + k46·x·y⁵</td></tr>
<tr><td class="name">カスタム</td><td class="math">k1 + k3·x + k5·y + k7·x² + k9·x·y + k11·y² + k13·x³ + k15·x²·y + k17·x·y² + k19·y³ + k21·x⁴ + k23·x³·y + k25·x²·y² + k27·x·y³ + k29·y⁴ + k31·x⁵ + k33·x⁴·y + k35·x³·y² + k37·x²·y³</td><td class="math">k2 + k4·y + k6·x + k8·y² + k10·x·y + k12·x² + k14·y³ + k16·x·y² + k18·x²·y + k20·x³ + k22·y⁴ + k24·x·y³ + k26·x²·y² + k28·x³·y + k30·x⁴ + k32·y⁵ + k34·x·y⁴ + k36·x²·y³ + k38·x³·y²</td></tr>
</tbody></table></div>
<p>カスタム・2次の番号の付け方は Canon・Nikon と同じ（dx は奇数の k で x<sup>n</sup>, x<sup>n−1</sup>y, …, y<sup>n</sup> の順、dy は偶数の k で y<sup>n</sup>, x·y<sup>n−1</sup>, …, x<sup>n</sup> の順）です。
係数は mm の座標での値（定数 nm、1次 nm/mm = ppm、n 次 nm/mm<sup>n</sup>）。</p>"""),
    ("formula-target", "未知の座標の補正のモデルと補正の比較", """
<p>「5. 未知の座標の推定」の補正のモデル（このタブの補正）は、上の Overlay 補正（基準の補正）とは別に選びます
（<code>alignest.targetCorrectionChoice</code>）。未知の座標の推定値を足すと Shot 内の点が増えるので、Shot 共通成分に高次の式を使えます。</p>
<div class="formula">このタブの補正の補正量(点) = Wafer 成分<sub>0〜5次</sub>(X, Y) + Shot 共通成分<sub>式</sub>(x, y) + Shot ごとの成分<sub>なし・並進・1次</sub>(x, y)
使う項：式のすべての項から、表のチェックで外した項を除く（0次・1次の項は外さない）
補正に使う点：元の実測値（学習点）＋ 学習しなかった Mark の推定値 ＋ 未知の座標の推定値（Wafer の外の点は除く）</div>
<p>「全計測と比べる」では、補正量を計測値のある Mark に当てた「計測値 − 補正量」で 4 つの補正を比べます
（<code>alignest.targetCorrectionComparison</code>）。</p>
<div class="formula">M：計測値のある Mark、　A：M の計測値、　E：学習点は計測値・学習しなかった Mark は推定値、　T：未知の座標の推定値
① 全計測｜基準の補正　　　　　　　　　　　　　残差 = A − 補正量<sub>基準</sub>(A)
② 一部計測＋面内推定｜基準の補正　　　　　　　残差 = A − 補正量<sub>基準</sub>(E)
③ 全計測＋未知の座標｜このタブの補正　　　　　残差 = A − 補正量<sub>このタブ</sub>(A ＋ T<sub>全 Mark で推定</sub>)
④ 一部計測＋面内推定＋未知の座標｜このタブの補正　残差 = A − 補正量<sub>このタブ</sub>(E ＋ T<sub>学習パターンで推定</sub>)
代表値　M の残差の |平均| + 3σ（X・Y 別）</div>
<p>④ が ② より小さければ、未知の座標の推定値を足した高次の補正で、一部計測でも重ね合わせがよくなる見込みです。① は全計測で基準の補正をしたときの目安です。</p>"""),
    ("formula-highorder", "Shot 高次補正の回帰と評価", """
<p>「6. Shot高次補正」の当てはめと評価の式です（<code>alignest.robustRidgeFit</code>・<code>alignest.shotHighOrder</code>）。</p>
<div class="formula">値(Mark) = Wafer 成分(Xc, Yc) + Σ<sub>使う項</sub> k<sub>j</sub>·x<sup>m</sup>y<sup>n</sup>　（k の組はくくり：Wafer 内で共通・選択 Wafer で共通・Scan 方向ごと・行の偶奇ごと・Shot ごと）
最小二乗：(1/2n) Σ r<sub>i</sub><sup>2</sup> + 罰則
Huber　 ：(1/n) Σ s<sup>2</sup> ρ<sub>c</sub>(r<sub>i</sub>/s) + 罰則　（重み w<sub>i</sub> = min(1, c·s/|r<sub>i</sub>|)）
LAD　　 ：(1/n) Σ s|r<sub>i</sub>| + 罰則　（重み w<sub>i</sub> = s / max(|r<sub>i</sub>|, 0.1·s)）
罰則　L2：(λ/2) Σ<sub>選んだ次数の項</sub> θ<sub>j</sub><sup>2</sup>、　L1：λ Σ<sub>選んだ次数の項</sub> |θ<sub>j</sub>|　（列を平均 0・標準偏差 1 にそろえた係数 θ）
s = 1.4826 × MAD（残差の中央値からの絶対偏差の中央値）</div>
<div class="formula">補正の評価　|平均| + 3σ（補正前の値・Wafer 高次補正だけ・＋Shot 共通補正・Shot ごとの 1 次・高次補正の残差）
外れ値を除いた |平均| + 3σ：Wafer ごと・軸ごとに、高次補正の残差 r の中央値 m と MAD から
　|r − m| &gt; n × 1.4826 × MAD の点を外れ値として除き、残りの |平均| + 3σ を求める（n は初期値 3。MAD = 0 なら除かない）
決定係数 R<sup>2</sup> = 1 − 残差の二乗和 / 値の平均からの二乗和</div>"""),
]
