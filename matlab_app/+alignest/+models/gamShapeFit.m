function result = gamShapeFit(setupFcn, gpTerms, candidates, y)
%GAMSHAPEFIT 形状関数にガウス過程回帰を含む GAM を、長さスケールを候補から REML で選んで当てはめる。
%   result = alignest.models.gamShapeFit(setupFcn, gpTerms, candidates, y)
%   setupFcn(lengthScales) は gamSetup の結果を返す関数（lengthScales は項の名前をフィールドに持つ構造体）。
%   gpTerms はガウス過程回帰にする項の名前（"xy"・"r"）、candidates は長さスケールの候補。
%   初めは全項を候補の真ん中にし、項ごとに（ほかの項は固定して）候補を順に試して、REML の基準
%   −2 l_R（罰則の擬似行列式も含めて、基底の違う模型どうしを比べられるようにした値）が最も小さい長さスケールを使う（1巡）。
%   ガウス過程の項が無ければ、長さスケールを選ばずにそのまま当てはめる（スプラインだけの GAM と同じ結果）。
%   result は gamFitPredict の結果に lengthScales（選んだ長さスケール）と nFits（当てはめた回数）を加えたもの。
IMPROVEMENT_TOLERANCE = 1e-8;
gpTerms = string(gpTerms(:)).';
candidates = sort(unique(candidates(:))).';
if isempty(gpTerms)
    result = alignest.models.gamFitPredict(setupFcn(struct()), y);
    result.lengthScales = struct();
    result.nFits = 1;
    return
end
if isempty(candidates) || any(~isfinite(candidates) | candidates <= 0)
    error('alignest:gamLengthScale', 'GAM のガウス過程の長さスケールの候補は正の数を1つ以上にしてください。');
end
scales = struct();
for term = gpTerms
    scales.(term) = candidates(ceil(numel(candidates) / 2));
end
[result, bestScore] = fitAndScore(setupFcn, scales, y);
nFits = 1;
for term = gpTerms
    evaluated = scales.(term);  % この項の今の値は当てはめ済み（候補の途中で値が変わっても同じ値を2回試さない）
    for candidate = candidates
        if candidate == evaluated
            continue
        end
        trial = scales;
        trial.(term) = candidate;
        [trialResult, score] = fitAndScore(setupFcn, trial, y);
        nFits = nFits + 1;
        if score < bestScore - IMPROVEMENT_TOLERANCE * max(abs(bestScore), 1)
            result = trialResult;
            bestScore = score;
            scales = trial;
        end
    end
end
result.lengthScales = scales;
result.nFits = nFits;
end

function [result, score] = fitAndScore(setupFcn, scales, y)
model = setupFcn(scales);
result = alignest.models.gamFitPredict(model, y);
score = result.criterion - model.logPseudoDetPenalty;
end
