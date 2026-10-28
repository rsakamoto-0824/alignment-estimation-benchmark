function conflicts = extensionConflicts(evaluated, requested)
%EXTENSIONCONFLICTS 評価済みの結果に条件を足すとき、評価したときと違ってはいけない設定の名前（違いが無ければ空）。
%   conflicts = alignest.extensionConflicts(評価したときの設定, これから実行する設定)
%   足してよいのは、手法の選択（説明変数の組・GPR のカーネル・質的変数の扱い、TPS などの有無、次数など）と、
%   質的変数の組（変えると、足す手法の id に使う組を付ける。alignest.runEvaluation・alignest.tagFactorSet）と、学習パターンの数
%   （学習 Shot 数・計測率の開始・終了・刻み、手動の行、ランダムの繰り返し回数、Mark 単位の 1 Shot あたりの数）。
%   推定の結果を変える次の設定は
%   同じでなければならない（違うと、評価済みの行と新しい行を同じ条件で比べられないため）。
%   データの読み込み・学習 Shot の選び方と制約（同心円・4象限・Scan 方向・許容幅・基準モデル・交換法・
%   乱数の種・必ず計測する Shot・優先順のファイル）・評価（外周の半径・1次を除く・異常値の除外・処理時間の記録）・
%   Overlay 補正の評価・手法の細かい設定（options）。表示の設定（display：Scan 方向の色・向き）は比べない。
COUNT_FIELDS = ["nShots", "nShotsStart", "nShotsEnd", "nShotsStep", "countBy", "rateStart", "rateEnd", "rateStep", ...
    "manualPlans", "randomRepeats", "markPerShot"];
GROUPS = ["data", "sampling", "options", "evaluation", "overlay"];
NAMES = ["データの読み込みの条件", "学習 Shot の選び方・制約", "手法の細かい設定", ...
    "評価の条件（外周の半径・1次を除く・異常値の除外・処理時間の記録）", "Overlay 補正の評価"];
evaluated = comparable(evaluated, COUNT_FIELDS);
requested = comparable(requested, COUNT_FIELDS);
conflicts = strings(1, 0);
for k = 1:numel(GROUPS)
    if ~isequaln(fieldOrEmpty(evaluated, GROUPS(k)), fieldOrEmpty(requested, GROUPS(k)))
        conflicts(end + 1) = NAMES(k); %#ok<AGROW>
    end
end
end

function settings = comparable(settings, countFields)
% 比べる部分だけを残す（学習パターンの数の項目を除き、手法は細かい設定 options だけ）
settings = alignest.upgradeRadiusSettings(settings);
settings.options = alignest.completeMethodSettings(settings.methods).options;
if isfield(settings, "factors") && isfield(settings.factors, "evaluateSingles")
    settings.factors = rmfield(settings.factors, "evaluateSingles");   % 手法を足すだけなので、条件の追加でよい
end
for name = countFields
    if isfield(settings.sampling, name)
        settings.sampling = rmfield(settings.sampling, name);
    end
end
end

function value = fieldOrEmpty(settings, name)
value = [];
if isfield(settings, name)
    value = settings.(name);
end
end
