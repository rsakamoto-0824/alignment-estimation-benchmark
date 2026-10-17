function [criterion, coef, edf] = gamCriterion(model, log10Lambda, xty, yty)
%GAMCRITERION 制限付き最尤（REML）の基準 −2 l_R（定数を除く）・係数・有効自由度。
%   −2 l_R(λ) = (n − M_p) log σ̂² + log|XᵀX + S_λ| − Σ_j r_j log λ_j、σ̂² = (RSS + β̂ᵀS_λβ̂)/(n − M_p)
%   （M_p は罰則のない係数の数、r_j は j 番目の罰則行列の階数）
system = model.gram + penaltyMatrix(model, log10Lambda);
[upperFactor, failed] = chol(system);
if failed
    criterion = Inf;
    coef = zeros(model.nCoef, 1);
    edf = model.n;
    return
end
inverseFactor = upperFactor \ eye(model.nCoef);
systemInverse = inverseFactor * inverseFactor.';
coef = systemInverse * xty;
edf = sum(systemInverse .* model.gram, 'all');
rss = max(yty - 2 * coef.' * xty + coef.' * model.gram * coef, 0);
penaltyValue = 0;
for k = 1:numel(model.penalties)
    columns = model.penalties(k).columns;
    penaltyValue = penaltyValue + 10^log10Lambda(k) * (coef(columns).' * model.penalties(k).matrix * coef(columns));
end
dof = model.n - model.nUnpenalized;
sigma2 = (rss + penaltyValue) / dof;
if sigma2 <= 0
    criterion = Inf;
    return
end
logDet = 2 * sum(log(diag(upperFactor)));
logDetPenalty = sum(model.penaltyRanks(:) .* log10Lambda(:) * log(10));
criterion = dof * log(sigma2) + logDet - logDetPenalty;
end

function total = penaltyMatrix(model, log10Lambda)
total = model.ridge * eye(model.nCoef);
for k = 1:numel(model.penalties)
    columns = model.penalties(k).columns;
    total(columns, columns) = total(columns, columns) + 10^log10Lambda(k) * model.penalties(k).matrix;
end
end
