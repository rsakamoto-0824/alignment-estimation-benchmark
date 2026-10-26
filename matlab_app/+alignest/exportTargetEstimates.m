function exportTargetEstimates(filePath, estimates, notes, spec, overlay)
%EXPORTTARGETESTIMATES 未知の座標での推定値を Excel ファイル（.xlsx）に書き出す。
%   alignest.exportTargetEstimates(filePath, estimates, notes, spec, overlay)
%   estimates：alignest.predictTargets の result.table に、Wafer の列（wafer）と学習データの列（training。省略可）を
%   足して縦に並べた表（Wafer × 学習データの組み合わせごと）。
%   notes：「説明」シートに足す行（[項目, 内容] の2列の文字列）。
%   「推定値」シート：Wafer・学習データ・名前・Xmm・Ymm・markXmm・markYmm・markNo・shotNo・Direction（読み込む表と
%   同じ見出しなので、このシートを alignest.readTargetPoints でそのまま読める）・Wafer 上の x・y・推定値 X・Y [nm]・
%   外挿・対象外（Wafer の外の点は推定値 0）・学習範囲の外 [mm]・最も近い学習点 [mm]・メモ。
%   「説明」シート：作成日時・外挿と Wafer の外の決め方・notes。
%   spec（alignest.valueSpec、省略可）が1変数なら、推定値は1列（「推定値 <値の名前>[<単位>]」）。
%   overlay（省略可）：重ね合わせ補正の結果。labels（組み合わせの名前）と results（組み合わせごとの
%   alignest.targetOverlayCorrection の結果。計算していない組み合わせは空）。計算した組み合わせがあれば、
%   「補正値」シート（係数）・「補正の残差」シート（点の種類ごとの |平均|+3σ）・「補正に使った点」シートを書く。
arguments
    filePath (1, 1) string
    estimates table
    notes (:, 2) string = strings(0, 2)
    spec struct = alignest.valueSpec(struct())
    overlay struct = struct("labels", strings(1, 0), "results", {{}})
end
[~, ~, extension] = fileparts(filePath);
if ~strcmpi(extension, ".xlsx")
    error('alignest:exportType', '書き出し先は .xlsx にしてください: %s', filePath);
end
if height(estimates) == 0
    error('alignest:noTargets', '書き出す推定値がありません。先に「推定する」を押してください。');
end
if isfile(filePath)
    try
        delete(filePath);
    catch err
        error('alignest:exportLocked', '「%s」を置き換えられません（Excel で開いていないか確かめてください）。理由: %s', ...
            filePath, err.message);
    end
end
items = ["作成日時"; "点の数"; "推定値"; "外挿"; "Wafer の外"; notes(:, 1)];
values = [string(datetime('now', 'Format', 'yyyy/MM/dd HH:mm:ss')); string(height(estimates)); ...
    "学習データ（計測値）から推定した値 [nm]。Wafer 上の座標は x = Xmm + markXmm、y = Ymm + markYmm [mm]。"; ...
    "学習点を囲む凸包の外にある点を「外挿」とする（凸包の外への距離が「学習範囲の外」）。学習点から離れるほど" + ...
    "推定値は信頼できない。学習に無い Mark 番号の点は、Mark 番号の効果を全 Mark の平均として推定する。"; ...
    "300 mm Wafer の外（半径 150 mm 以上）の点は推定の対象外とし、推定値を X・Y とも 0 にした。"; notes(:, 2)];
writetable(table(items, values, 'VariableNames', ["項目", "内容"]), filePath, 'Sheet', '説明');
n = height(estimates);
mark = strings(n, 1);
mark(estimates.extrapolated) = "外挿";
training = strings(n, 1);
if any(string(estimates.Properties.VariableNames) == "training")
    training = estimates.training;
end
if any(string(estimates.Properties.VariableNames) == "outsideWafer")
    mark(estimates.outsideWafer) = "Wafer の外（対象外）";
end
sheet = table(estimates.wafer, training, estimates.name, estimates.Xmm, estimates.Ymm, estimates.markXmm, ...
    estimates.markYmm, estimates.markNo, estimates.shotNo, estimates.direction, estimates.x, estimates.y, ...
    estimates.estimateX, estimates.estimateY, mark, estimates.outsideMm, estimates.nearestMm, estimates.note, ...
    'VariableNames', ["Wafer", "学習データ", "名前", "Xmm", "Ymm", "markXmm", "markYmm", "markNo", "shotNo", ...
    "Direction", "x[mm]", "y[mm]", "推定値X[nm]", "推定値Y[nm]", "外挿・対象外", "学習範囲の外[mm]", ...
    "最も近い学習点[mm]", "メモ"]);
if spec.scalar
    sheet = removevars(sheet, "推定値Y[nm]");
    sheet.Properties.VariableNames{'推定値X[nm]'} = char("推定値 " + spec.name + "[" + spec.unit + "]");
end
writetable(sheet, filePath, 'Sheet', '推定値');
writeOverlay(filePath, overlay);
end

function writeOverlay(filePath, overlay)
% 計算した組み合わせの重ね合わせ補正値（係数）・残差・補正に使った点を、組み合わせの列を付けて縦に並べる
[coefficientParts, summaryParts, pointParts] = deal({});
for k = 1:numel(overlay.results)
    correction = overlay.results{k};
    if isempty(correction)
        continue
    end
    label = overlay.labels(k);
    coefficients = correction.coefficients;
    coefficientParts{end + 1, 1} = table(repmat(label, height(coefficients), 1), coefficients.axis, ...
        coefficients.componentLabel, coefficients.shotNo, coefficients.term, coefficients.value, coefficients.unit, ...
        coefficients.note, 'VariableNames', ["組み合わせ", "軸", "成分", "shotNo", "項", "補正値(係数)", "単位", ...
        "メモ"]); %#ok<AGROW>
    summary = correction.summary;
    summaryParts{end + 1, 1} = table(repmat(label, height(summary), 1), summary.axis, summary.source, summary.n, ...
        summary.valueMean3Sigma, summary.residualMean3Sigma, repmat(correction.description, height(summary), 1), ...
        'VariableNames', ["組み合わせ", "軸", "点の種類", "点数", "補正前の|平均|+3σ[nm]", ...
        "補正後の残差の|平均|+3σ[nm]", "補正モデル"]); %#ok<AGROW>
    points = correction.points;
    pointParts{end + 1, 1} = table(repmat(label, height(points), 1), points.source, points.name, points.shotNo, ...
        points.x, points.y, points.valueX, points.valueY, points.correctionX, points.correctionY, points.residualX, ...
        points.residualY, 'VariableNames', ["組み合わせ", "点の種類", "名前", "shotNo", "x[mm]", "y[mm]", "値X[nm]", ...
        "値Y[nm]", "補正量X[nm]", "補正量Y[nm]", "補正後の残差X[nm]", "補正後の残差Y[nm]"]); %#ok<AGROW>
end
if isempty(coefficientParts)
    return
end
writetable(vertcat(coefficientParts{:}), filePath, 'Sheet', '補正値');
writetable(vertcat(summaryParts{:}), filePath, 'Sheet', '補正の残差');
writetable(vertcat(pointParts{:}), filePath, 'Sheet', '補正に使った点');
end
