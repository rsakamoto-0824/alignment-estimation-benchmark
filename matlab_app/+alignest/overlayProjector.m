function projector = overlayProjector(unit, choice, waferRadiusMm)
%OVERLAYPROJECTOR 補正モデルの最小二乗の当てはめを、軸ごとの射影（補正量 = 基底 · 基底ᵀ · 値）として前計算する。
%   補正モデル = Wafer 成分 + Shot 共通成分 + Shot ごとの成分（alignest.overlayChoice）を X・Y 別々に当てはめる。
%   - Wafer 成分     ：Shot 中心の座標（Xmm・Ymm を Wafer 半径で割った値）の多項式（次数 choice.waferOrder）、
%                      または入力した式（choice.waferTerms。x・y は Shot 中心の座標を Wafer 半径で割った値）
%   - Shot 共通成分  ：Shot 内の座標（markXmm・markYmm）の補正式（alignest.overlayTerms、または入力した式
%                      choice.shotTerms）。全 Shot で同じ係数
%   座標を割る値（Wafer 半径・LOCAL_SCALE_MM）は、べき乗の桁をそろえるためだけで、補正量（射影）は変わらない。
%   - Shot ごとの成分：Shot ごとに並進（k1・k2）・1次（k1〜k6）、または入力した式（choice.perShotTerms。x・y は
%                      Shot 内の座標）の係数を持つ（同じ式の係数を Shot ごとに別々に求める）
%   成分どうしで重なる項（例：Wafer 成分の定数と k1）や、Mark の位置が少なくて決まらない項があっても、
%   当てはめた補正量（射影）は一つに決まるので、係数を求めずに列空間の正規直交基底で射影する。
%   projector.X・.Y は index（その軸が有効な Mark の番号）と basis（正規直交基底）。設計行列は alignest.overlayDesign。
marks = unit.marks;
axisNames = ["X", "Y"];
for k = 1:2
    index = find(marks.("valid" + axisNames(k)));
    design = alignest.overlayDesign(marks, choice, waferRadiusMm, k, index);
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
