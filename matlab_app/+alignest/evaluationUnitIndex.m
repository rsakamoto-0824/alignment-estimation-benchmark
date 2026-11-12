function [index, text] = evaluationUnitIndex(nUnits, evaluation, seed)
%EVALUATIONUNITINDEX 読み込んだ Wafer（評価の単位）のうち、評価に使う Wafer の番号（data.units の何番目か。小さい順）。
%   [index, text] = alignest.evaluationUnitIndex(nUnits, settings.evaluation, settings.sampling.seed)
%   evaluation.waferSelection："all"（すべて。既定）・"count"（waferCount 枚）・"rate"（waferRate [%]。読み込んだ枚数 ×
%   割合 を四捨五入、1 枚以上）。evaluation.waferOrder："first"（先頭から順に。既定）・"random"（乱数の種 seed で決まる
%   並びから。同じ種なら同じ Wafer）。枚数・割合を増やしたときの Wafer は、少ないときの Wafer をすべて含む（同じ並びの先頭から
%   取るので、条件の追加で Wafer を足せる。alignest.runEvaluation）。読み込んだ枚数より多い枚数はすべて。
%   text：画面に出す説明（例 "5 枚中 3 枚（先頭から）"）
arguments
    nUnits (1, 1) double {mustBeNonnegative, mustBeInteger}
    evaluation struct
    seed (1, 1) double = 0
end
selection = string(fieldOr(evaluation, "waferSelection", "all"));
order = string(fieldOr(evaluation, "waferOrder", "first"));
switch selection
    case "all"
        n = nUnits;
    case "count"
        count = double(fieldOr(evaluation, "waferCount", nUnits));
        if ~isscalar(count) || ~isfinite(count) || count < 1 || count ~= round(count)
            error('alignest:waferSelection', '評価に使う Wafer の枚数は 1 以上の整数にしてください。');
        end
        n = min(count, nUnits);
    case "rate"
        rate = double(fieldOr(evaluation, "waferRate", 100));
        if ~isscalar(rate) || ~isfinite(rate) || rate <= 0 || rate > 100
            error('alignest:waferSelection', '評価に使う Wafer の割合は 0 より大きく 100 以下 [%%] にしてください。');
        end
        n = min(nUnits, max(1, round(rate / 100 * nUnits)));
    otherwise
        error('alignest:waferSelection', '評価に使う Wafer の決め方は all・count・rate のいずれかです: %s', selection);
end
if ~any(order == ["first", "random"])
    error('alignest:waferSelection', '評価に使う Wafer の選び方は first・random のいずれかです: %s', order);
end
if order == "random" && n < nUnits
    stream = RandStream('mt19937ar', 'Seed', seed);
    sequence = randperm(stream, nUnits);
    index = sort(sequence(1:n));
else
    index = 1:n;
end
orderText = struct("first", "先頭から", "random", "ランダム");
if n == nUnits
    text = sprintf("%d 枚すべて", nUnits);
else
    text = sprintf("%d 枚中 %d 枚（%s）", nUnits, n, orderText.(order));
end
end

function value = fieldOr(s, name, fallback)
value = fallback;
if isfield(s, name) && ~isempty(s.(name))
    value = s.(name);
end
end
