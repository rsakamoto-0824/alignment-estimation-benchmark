function result = correctionVarianceDecomposition(comparison, methodPlan, scope)
%CORRECTIONVARIANCEDECOMPOSITION 補正前の値と、実測値・推定値で補正した残差のばらつき分解（「4. 結果一覧」の
%   「補正残差のばらつき分解」）。補正で Lot 間・Wafer 間・Scan 方向間・Shot 間・その他のばらつきがどう変わるかを比べる。
%   result = alignest.correctionVarianceDecomposition(comparison, methodPlan, scope)
%   comparison：「実測値と推定値の補正」の結果（alignest.estimatedCorrectionComparison。points・stageNames・stageUsed を使う）。
%   methodPlan：手法と学習パターン（"手法の名前｜学習パターン"。省略・"" なら1つ目）、scope："すべての点"（既定）・
%   "推定対象の点"（学習に使わなかった Mark）。
%   棒（category）：補正前の値、補正の段階（足す成分のある段階。Wafer 成分・＋Shot 共通・全成分）ごとの実測値で補正した
%   残差と推定値で補正した残差。どの棒も同じ点（軸ごとに、全成分の残差が実測値・推定値の両方である点）で分ける
%   （alignest.varianceDecomposition。Lot 間は Lot が2つ以上、Scan 方向間は Scan 方向の分かる点があるとき）。
%   result：alignest.varianceDecomposition の結果に、methodPlans（選べる手法｜学習パターン）・methodPlan・scope・nWafers
%   （Wafer の数）・categoryNames（棒の長い名前）・unitLabel を足したもの
arguments
    comparison struct
    methodPlan (1, 1) string = ""
    scope (1, 1) string {mustBeMember(scope, ["すべての点", "推定対象の点"])} = "すべての点"
end
BEFORE_NAME = "補正前";
if ~isfield(comparison, "points") || isempty(comparison.points)
    error('alignest:varianceDecomposition', '先に「実測値と推定値の補正」で比べてください（点ごとの値がありません）。');
end
points = comparison.points;
methodPlans = unique(points.method + "｜" + points.plan, 'stable');
if methodPlan == ""
    methodPlan = methodPlans(1);
end
if ~any(methodPlans == methodPlan)
    error('alignest:varianceDecomposition', '手法・学習パターン「%s」の結果がありません。', methodPlan);
end
points = points(points.method + "｜" + points.plan == methodPlan, :);
inScope = true(height(points), 1);
if scope == "推定対象の点"
    inScope = points.target;
end
% 棒：補正前、足す成分のある段階ごとに実測値で補正・推定値で補正
stages = find(comparison.stageUsed);
shortNames = BEFORE_NAME;
longNames = "補正前の値";
for s = stages
    shortNames = [shortNames, "実測・" + comparison.stageNames(s), "推定・" + comparison.stageNames(s)]; %#ok<AGROW>
    longNames = [longNames, "実測値で補正（" + comparison.stageNames(s) + "まで）", ...
        "推定値で補正（" + comparison.stageNames(s) + "まで）"]; %#ok<AGROW>
end
axisColumns = ["X", "Y"];
parts = cell(numel(shortNames), 1);
for b = 1:numel(shortNames)
    values = nan(height(points), 2);
    for a = 1:2
        measured = points.("measured" + axisColumns(a));
        estimated = points.("estimated" + axisColumns(a));
        compared = inScope & isfinite(measured(:, end)) & isfinite(estimated(:, end));   % 「実測値と推定値の補正」と同じ点
        if b == 1
            column = points.actual(:, a);
        else
            stage = stages(ceil((b - 1) / 2));
            if mod(b, 2) == 0
                column = measured(:, stage);
            else
                column = estimated(:, stage);
            end
        end
        column(~compared) = NaN;
        values(:, a) = column;
    end
    parts{b} = table(repmat(shortNames(b), height(points), 1), points.lot, points.wafer, points.scan, points.shot, ...
        values(:, 1), values(:, 2), 'VariableNames', ["category", "lot", "wafer", "scan", "shot", "valueX", "valueY"]);
end
long = vertcat(parts{:});
result = alignest.varianceDecomposition(long, categories=shortNames);
result.methodPlans = reshape(methodPlans, 1, []);
result.methodPlan = methodPlan;
result.scope = scope;
result.nWafers = numel(unique(points.wafer));
result.categoryNames = longNames;
result.unitLabel = "nm";
end
