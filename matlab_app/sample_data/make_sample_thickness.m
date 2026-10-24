%MAKE_SAMPLE_THICKNESS 1変数・絶対座標の動作確認用サンプル（膜厚の模擬データ）を CSV に書き出す。
%   matlab_app を現在のフォルダにして run('sample_data/make_sample_thickness.m') を実行する。
%   Wafer 5 枚 × 109 点（中心と同心円 6 本）。座標は Wafer 上の絶対座標（Xmm・Ymm の列、Shot の情報は無い）、
%   推定する値は Thickness_nm の列（膜厚 [nm]）。値は式と乱数で作ったもので、実データ・社内データは使っていない。
%   膜厚 = 100 + 2.0·ρ² − 1.2·ρ⁴ + 0.4·(x/R) + 0.3·ρ³·sin 3θ + Wafer ごとのずれ + 測定ばらつき（ρ = r/R、R = 150 mm）。
%   Chamber の列（A・B）は質的変数を試すための列（Chamber B は 0.15 nm 厚い）。
SEED = 20261025;
WAFER_RADIUS_MM = 150;
RING_RADII_MM = [0, 25, 50, 75, 100, 125, 145];
RING_COUNTS = [1, 8, 12, 16, 20, 24, 28];          % 合計 109 点
WAFER_IDS = "THK01-" + compose("%02d", (1:5).');  % ハイフンの後が Slot 番号
CHAMBERS = ["A", "B", "A", "B", "A"];
WAFER_OFFSET_SD_NM = 0.2;
NOISE_SD_NM = 0.05;
CHAMBER_B_OFFSET_NM = 0.15;
OUTPUT = fullfile(fileparts(mfilename('fullpath')), 'sample_thickness.csv');

stream = RandStream('mt19937ar', 'Seed', SEED);
[x, y] = deal(zeros(0, 1));
for k = 1:numel(RING_RADII_MM)
    angle = 2 * pi * (0:RING_COUNTS(k) - 1).' / RING_COUNTS(k) + pi / RING_COUNTS(k) * mod(k, 2);
    x = [x; RING_RADII_MM(k) * cos(angle)]; %#ok<AGROW>
    y = [y; RING_RADII_MM(k) * sin(angle)]; %#ok<AGROW>
end
x = round(x, 3);
y = round(y, 3);
rho = hypot(x, y) / WAFER_RADIUS_MM;
theta = atan2(y, x);
shape = 100 + 2.0 * rho.^2 - 1.2 * rho.^4 + 0.4 * x / WAFER_RADIUS_MM + 0.3 * rho.^3 .* sin(3 * theta);
rows = cell(numel(WAFER_IDS), 1);
for w = 1:numel(WAFER_IDS)
    offset = WAFER_OFFSET_SD_NM * randn(stream) + CHAMBER_B_OFFSET_NM * (CHAMBERS(w) == "B");
    thickness = round(shape + offset + NOISE_SD_NM * randn(stream, numel(x), 1), 4);
    n = numel(x);
    rows{w} = table(repmat(WAFER_IDS(w), n, 1), x, y, thickness, repmat(CHAMBERS(w), n, 1), ...
        'VariableNames', ["Wafer", "Xmm", "Ymm", "Thickness_nm", "Chamber"]);
end
writetable(vertcat(rows{:}), OUTPUT);
fprintf('%s に %d 行を書き出しました。\n', OUTPUT, sum(cellfun(@height, rows)));
