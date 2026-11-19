function selected = sobolShots(centersMm, nSelect, fixed, waferRadiusMm)
%SOBOLSHOTS Sobol 列の点に近い Shot を学習 Shot に選ぶ（Wafer 上に偏りなく散らばる計測配置。最適化はしない）。
%   selected = alignest.sobolShots(centersMm, nSelect, fixed, waferRadiusMm)
%   centersMm：選べる Shot の中心 [x, y]（mm。行が Shot）、nSelect：選ぶ数、fixed：必ず選ぶ Shot（論理値。先に入れる）、
%   waferRadiusMm：Wafer の半径。selected：選んだ Shot（centersMm の行番号。選んだ順）。
%   選び方：Sobol 列（alignest.sobolSequence）の点を Wafer を囲む正方形 [−R, R]² に置き、Wafer の外の点は飛ばす。
%   前の点から順に、点に最も近い Shot（すべての Shot の中で）がまだ選ばれていなければ選ぶ（選ばれていれば、その点は飛ばす。
%   同じ場所に集まらないように）。点を MAX_POINTS_PER_SHOT × Shot の数まで使っても足りなければ、残りは点に最も近い
%   まだ選んでいない Shot を選ぶ。乱数は使わないので、同じ Shot の配置なら同じ Shot を選ぶ。
arguments
    centersMm (:, 2) double
    nSelect (1, 1) double {mustBeInteger, mustBeNonnegative}
    fixed logical = false(0, 1)
    waferRadiusMm (1, 1) double {mustBePositive} = 150
end
MAX_POINTS_PER_SHOT = 64;   % 点に近い Shot が選ばれてばかりのとき、点を使い切るまでの目安（Shot の数の何倍か）
nShots = size(centersMm, 1);
fixed = reshape(fixed, [], 1);
if isempty(fixed)
    fixed = false(nShots, 1);
end
if numel(fixed) ~= nShots
    error('alignest:sobolShots', '必ず選ぶ Shot の数が Shot の数と合いません。');
end
if nSelect > nShots
    error('alignest:sobolShots', '選ぶ数 %d が Shot の数 %d より多いです。', nSelect, nShots);
end
chosen = fixed;
selected = find(fixed);
if numel(selected) >= nSelect
    return
end
points = (2 * alignest.sobolSequence(MAX_POINTS_PER_SHOT * nShots) - 1) * waferRadiusMm;
points = points(hypot(points(:, 1), points(:, 2)) < waferRadiusMm, :);   % Wafer の中の点だけ
for p = 1:size(points, 1)
    [~, nearest] = min((centersMm(:, 1) - points(p, 1)) .^ 2 + (centersMm(:, 2) - points(p, 2)) .^ 2);
    if ~chosen(nearest)
        chosen(nearest) = true;
        selected(end + 1, 1) = nearest; %#ok<AGROW>
        if numel(selected) >= nSelect
            return
        end
    end
end
% 足りなければ、点の順に、点に最も近いまだ選んでいない Shot
for p = 1:size(points, 1)
    remaining = find(~chosen);
    [~, nearest] = min((centersMm(remaining, 1) - points(p, 1)) .^ 2 + (centersMm(remaining, 2) - points(p, 2)) .^ 2);
    chosen(remaining(nearest)) = true;
    selected(end + 1, 1) = remaining(nearest); %#ok<AGROW>
    if numel(selected) >= nSelect
        return
    end
end
end
