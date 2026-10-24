function targets = targetTemplate(nRows)
%TARGETTEMPLATE 未知の座標（推定したい点）の表の形。
%   targets = alignest.targetTemplate()        % 0 行
%   targets = alignest.targetTemplate(nRows)   % nRows 行（名前は空、Shot 内の座標は 0、それ以外は NaN）
%   列：name（点の名前）・Xmm・Ymm（Shot 中心の座標 [mm]。Shot 内の座標が 0 なら点そのものの Wafer 上の座標）・
%   markXmm・markYmm（Shot 中心から見た点の座標 [mm]）・markNo（Mark 番号）・shotNo・direction（Scan 方向 1・2）。
%   Wafer 上の座標は計測データと同じく x = Xmm + markXmm、y = Ymm + markYmm。
%   markNo・shotNo・direction が NaN の点は、推定のときに分かる範囲で補う（alignest.predictTargets）。
arguments
    nRows (1, 1) double {mustBeInteger, mustBeNonnegative} = 0
end
targets = table(strings(nRows, 1), nan(nRows, 1), nan(nRows, 1), zeros(nRows, 1), zeros(nRows, 1), nan(nRows, 1), ...
    nan(nRows, 1), nan(nRows, 1), 'VariableNames', ...
    ["name", "Xmm", "Ymm", "markXmm", "markYmm", "markNo", "shotNo", "direction"]);
end
