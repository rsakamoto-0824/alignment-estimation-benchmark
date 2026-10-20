function model = rbfSetup(trainFeatures, testFeatures, lengthScales, log10Grid)
%RBFSETUP Gaussian RBF: phi(r) = exp(-r^2 / (2*ell^2)) と1次多項式。
% ell は Wafer 半径で正規化した説明変数の距離。候補ごとの分解を再利用する。
if isempty(lengthScales) || any(~isfinite(lengthScales) | lengthScales <= 0)
    error('alignest:rbfLengthScale', 'RBF の広がりには正の有限値を1つ以上指定してください。');
end
distance = alignest.basis.pairwiseSquaredDiff(trainFeatures, trainFeatures);
distanceTest = alignest.basis.pairwiseSquaredDiff(testFeatures, trainFeatures);
model.lengthScales = lengthScales(:);
model.candidates = cell(numel(lengthScales), 1);
for k = 1:numel(lengthScales)
    phi = exp(-distance / (2 * lengthScales(k)^2));
    phiTest = exp(-distanceTest / (2 * lengthScales(k)^2));
    model.candidates{k} = alignest.models.radialSetup(trainFeatures, testFeatures, phi, phiTest, log10Grid);
end
end
