function shapes = randomShotShapes(xMm, yMm, options)
%RANDOMSHOTSHAPES 乱数で Shot の形（Shot 内の座標の多項式の歪み）を作る（「8. Mark配置の最適化」で実測値の無い座標の評価に使う）。
%   shapes = alignest.randomShotShapes(xMm, yMm, shapes=200, seed=1, orderSigmaNm=[3, 3, 1.5, 1, 0.5, 0.3, 0, 0], noiseNm=0.5, ...
%       outlierPercent=0, outlierNm=10)
%   xMm・yMm：候補の Mark の Shot 内の座標 [mm]（Shot 中心から）。
%   形：dx・dy それぞれ、大きさを入れた次数（orderSigmaNm が 0 より大きい 0〜7次）の項 u^a·v^b（u = x / Rx、v = y / Ry。Rx・Ry は
%   候補の |x|・|y| の最大で、Shot の端で u・v が ±1）から、形ごとに項を乱数で選び（項ごとに TERM_SHARE の確率。1つも
%   選ばれなければ1項）、次数ごとの大きさ orderSigmaNm（Shot の端での標準偏差 [nm]）の正規乱数の重みを掛けて足す。補正の式に
%   無い項（高い次数など）も入るので、補正しきれない形も評価に入る。
%   計測した値 = 形 + 計測のばらつき（各点に標準偏差 noiseNm [nm] の正規乱数）+ 飛び値（点ごとの飛び値：Shot ごとに
%   round(候補の数 × outlierPercent / 100) 点を乱数で選び、大きさ outlierNm [nm]・向きは乱数の値を X・Y に足す）。
%   乱数は形ごとに別の流れ（mrg32k3a の Substream。形・ばらつき・飛び値も別）で作るので、同じ種なら、形の数・飛び値の割合を
%   変えても、同じ番号の形は同じになる。
%   shapes.trueX・trueY：形（計測のばらつき・飛び値を足す前。候補の数 × 形の数 [nm]）、measuredX・measuredY：計測した値、
%   outlier：飛び値の点（候補の数 × 形の数）、halfSizeMm：[Rx, Ry]、count：形の数、powers：項のべき [a, b]、coefficientsX・Y：
%   項の重み（項の数 × 形の数。alignest.randomShapeField）、representative：代表の形の番号（|形| の 95% 点が形の間の中央値に
%   最も近い形）。
arguments
    xMm double
    yMm double
    options.shapes (1, 1) double {mustBePositive, mustBeInteger} = 200
    options.seed (1, 1) double {mustBeNonnegative, mustBeInteger} = 1
    options.orderSigmaNm double = [3, 3, 1.5, 1, 0.5, 0.3, 0, 0]
    options.noiseNm (1, 1) double {mustBeNonnegative} = 0.5
    options.outlierPercent (1, 1) double {mustBeNonnegative} = 0
    options.outlierNm (1, 1) double {mustBeNonnegative} = 10
end
SHAPE_STREAMS = 0;          % 形の係数の流れ（Substream の番号 = 形の番号 + これ）
MAX_SHAPES = 1000;          % 形の数の上限（流れの番号を分けるため）
NOISE_STREAMS = MAX_SHAPES; % 計測のばらつきの流れ
OUTLIER_STREAMS = 2 * MAX_SHAPES;  % 飛び値の流れ
TERM_SHARE = 0.5;           % 形ごとに、大きさを入れた次数の項を選ぶ確率
x = reshape(xMm, [], 1);
y = reshape(yMm, [], 1);
n = numel(x);
if numel(y) ~= n || n == 0
    error('alignest:markLayout', '乱数の形を作る Mark の座標は、X・Y を同じ数だけ入れてください。');
end
if options.shapes > MAX_SHAPES
    error('alignest:markLayout', '乱数の Shot の形は %d 通りまでです。', MAX_SHAPES);
end
halfSize = [max(abs(x)), max(abs(y))];
halfSize(halfSize == 0) = 1;
u = x / halfSize(1);
v = y / halfSize(2);
sigma = reshape(options.orderSigmaNm, 1, []);
powers = zeros(0, 2);
termSigma = zeros(0, 1);
for order = 0:numel(sigma) - 1
    for j = 0:order
        powers(end + 1, :) = [order - j, j]; %#ok<AGROW>
        termSigma(end + 1, 1) = sigma(order + 1); %#ok<AGROW>
    end
end
basis = u .^ (powers(:, 1).') .* v .^ (powers(:, 2).');
nTerms = size(powers, 1);
nShapes = options.shapes;
nOutliers = round(n * options.outlierPercent / 100);
[trueX, trueY, noiseX, noiseY, outlierX, outlierY] = deal(zeros(n, nShapes));
[coefficientsX, coefficientsY] = deal(zeros(nTerms, nShapes));
active = find(termSigma > 0);
outlier = false(n, nShapes);
stream = RandStream('mrg32k3a', 'Seed', options.seed);
for s = 1:nShapes
    stream.Substream = SHAPE_STREAMS + s;
    picked = rand(stream, nTerms, 2) < TERM_SHARE & termSigma > 0;
    fallback = rand(stream, 1, 2);   % 1つも選ばれなかったときの項（乱数の流れがそろうよう、いつも引く）
    for a = 1:2
        if ~any(picked(:, a)) && ~isempty(active)
            picked(active(ceil(fallback(a) * numel(active))), a) = true;
        end
    end
    coefficients = termSigma .* randn(stream, nTerms, 2) .* picked;
    coefficientsX(:, s) = coefficients(:, 1);
    coefficientsY(:, s) = coefficients(:, 2);
    trueX(:, s) = basis * coefficients(:, 1);
    trueY(:, s) = basis * coefficients(:, 2);
    stream.Substream = NOISE_STREAMS + s;
    noise = options.noiseNm * randn(stream, n, 2);
    noiseX(:, s) = noise(:, 1);
    noiseY(:, s) = noise(:, 2);
    if nOutliers > 0
        stream.Substream = OUTLIER_STREAMS + s;
        picked = randperm(stream, n, nOutliers);
        angle = 2 * pi * rand(stream, nOutliers, 1);
        outlier(picked, s) = true;
        outlierX(picked, s) = options.outlierNm * cos(angle);
        outlierY(picked, s) = options.outlierNm * sin(angle);
    end
end
magnitude = zeros(1, nShapes);
for s = 1:nShapes
    magnitude(s) = alignest.stats.percentile(hypot(trueX(:, s), trueY(:, s)), 95);
end
[~, representative] = min(abs(magnitude - median(magnitude)));
shapes = struct("trueX", trueX, "trueY", trueY, "measuredX", trueX + noiseX + outlierX, ...
    "measuredY", trueY + noiseY + outlierY, "outlier", outlier, "halfSizeMm", halfSize, "count", nShapes, ...
    "powers", powers, "coefficientsX", coefficientsX, "coefficientsY", coefficientsY, "representative", representative);
end
