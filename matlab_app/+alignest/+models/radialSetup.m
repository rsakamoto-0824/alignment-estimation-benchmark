function model = radialSetup(trainFeatures, testFeatures, phi, phiTest, log10Grid)
%RADIALSETUP TPS・Gaussian RBF に共通する、1次多項式つき平滑化の前計算。
if isempty(log10Grid) || any(~isfinite(log10Grid))
    error('alignest:radialGrid', '平滑化の候補には有限の常用対数を1つ以上指定してください。');
end
n = size(trainFeatures, 1);
model.n = n;
model.phi = phi;
model.phiTest = phiTest;
[model.poly, model.polyTest] = alignest.basis.independentColumns( ...
    [ones(n, 1), trainFeatures], [ones(size(testFeatures, 1), 1), testFeatures]);
k = size(model.poly, 2);
if n <= k
    error('alignest:radialPoints', '学習点（%d 点）が多項式部分の項数（%d）以下です。学習 Shot を増やしてください。', n, k);
end
[qFull, rFull] = qr(model.poly);
model.q1 = qFull(:, 1:k);
model.r1 = rFull(1:k, :);
q2 = qFull(:, k + 1:end);
reduced = q2.' * phi * q2;
[vectors, values] = eig((reduced + reduced.') / 2, 'vector');
model.eigval = max(values, 0);
model.basis = q2 * vectors;
scale = mean(model.eigval);
if scale <= 0
    scale = 1;
end
model.nLambdaGrid = scale * 10 .^ log10Grid(:);
if any(~isfinite(model.nLambdaGrid) | model.nLambdaGrid <= 0)
    error('alignest:radialGrid', '平滑化の候補が小さすぎるか大きすぎます。');
end
end
