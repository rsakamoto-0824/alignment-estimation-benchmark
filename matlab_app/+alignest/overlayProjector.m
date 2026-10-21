function projector = overlayProjector(unit, choice, waferRadiusMm)
%OVERLAYPROJECTOR 補正モデルの最小二乗の当てはめを、軸ごとの射影（補正量 = 基底 · 基底ᵀ · 値）として前計算する。
%   補正モデル = Wafer 成分 + Shot 共通成分 + Shot ごとの成分（alignest.overlayChoice）を X・Y 別々に当てはめる。
%   - Wafer 成分     ：Shot 中心の座標（Xmm・Ymm を Wafer 半径で割った値）の多項式（次数 choice.waferOrder）
%   - Shot 共通成分  ：Shot 内の座標（markXmm・markYmm）の補正式（alignest.overlayTerms）。全 Shot で同じ係数
%   - Shot ごとの成分：Shot ごとに並進（k1・k2）または1次（k1〜k6）の係数を持つ
%   成分どうしで重なる項（例：Wafer 成分の定数と k1）や、Mark の位置が少なくて決まらない項があっても、
%   当てはめた補正量（射影）は一つに決まるので、係数を求めずに列空間の正規直交基底で射影する。
%   projector.X・.Y は index（その軸が有効な Mark の番号）と basis（正規直交基底）。
LOCAL_SCALE_MM = 10;  % Shot 内の座標を割る値（べき乗の桁をそろえるだけで、補正量は変わらない）
marks = unit.marks;
axisNames = ["X", "Y"];
for k = 1:2
    index = find(marks.("valid" + axisNames(k)));
    blocks = {zeros(numel(index), 0)};
    if choice.waferOrder > 0
        blocks{end + 1} = alignest.basis.polynomialDesign(marks.Xmm(index) / waferRadiusMm, ...
            marks.Ymm(index) / waferRadiusMm, choice.waferOrder); %#ok<AGROW>
    end
    localX = marks.markXmm(index) / LOCAL_SCALE_MM;
    localY = marks.markYmm(index) / LOCAL_SCALE_MM;
    if choice.shotCommon ~= "none"
        blocks{end + 1} = localTerms(alignest.overlayTerms(choice.shotCommon), k, localX, localY); %#ok<AGROW>
    end
    if choice.perShot ~= "none"
        perShotModel = "linear";
        local = localTerms(alignest.overlayTerms(perShotModel), k, localX, localY);
        if choice.perShot == "translation"
            local = local(:, 1);  % k1（X）・k2（Y）だけ
        end
        shots = marks.shotIndex(index);
        indicator = double(shots == unique(shots).');
        perShot = zeros(numel(index), size(indicator, 2) * size(local, 2));
        for term = 1:size(local, 2)
            perShot(:, (term - 1) * size(indicator, 2) + (1:size(indicator, 2))) = indicator .* local(:, term);
        end
        blocks{end + 1} = perShot; %#ok<AGROW>
    end
    design = [blocks{:}];
    basis = zeros(numel(index), 0);
    if ~isempty(design)
        [q, r, ~] = qr(design, 0);
        diagonal = abs(diag(r));
        rankValue = nnz(diagonal > max(size(design)) * eps(max(diagonal)));
        basis = q(:, 1:rankValue);
    end
    projector.(axisNames(k)) = struct("index", index, "basis", basis, "nTerms", size(design, 2), ...
        "rank", size(basis, 2));
end
projector.choice = choice;
end

function columns = localTerms(terms, axisIndex, localX, localY)
% 補正式の項を Shot 内の座標で評価する（X は dx の式、Y は dy の式）
if axisIndex == 1
    table_ = terms.dx;
else
    table_ = terms.dy;
end
columns = localX .^ (table_(:, 2).') .* localY .^ (table_(:, 3).');  % べきと転置は同じ優先順位なので括弧が必要
end
