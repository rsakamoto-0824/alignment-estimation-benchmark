function settings = defaultSettings()
%DEFAULTSETTINGS 初期設定。比べる手法は「推奨の組み合わせ」（前回の模擬データの評価で各系統の代表になった設定）。
settings.version = 1;

% データ（Overlay 計測ルール：300 mm Wafer、有効な点は r < 150 mm）
settings.data.waferRadiusMm = 150;      % 座標を割って単位をそろえる値（説明変数・基底関数）
settings.data.validRadiusMm = 150;      % この半径以上の点は除く
settings.data.coordinateUnits = alignest.coordinateUnits();
settings.factors.shotRowParity = false; % Shot 配列の行（上から1行目）の奇数・偶数を追加する

% 学習に使う Shot の選び方
settings.sampling.method = "ioptimal";  % ioptimal（制約付き I 最適）／random（制約つきランダム）／manual（手動）
settings.sampling.nShots = [10, 15, 20, 25, 30, 35, 40];
settings.sampling.randomRepeats = 10;
settings.sampling.seed = 20261017;
settings.sampling.manualPlans = strings(0, 1);
settings.sampling.designOrder = 5;      % I 最適の基準モデル（XY 多項式の次数、5次で21項）
settings.sampling.exchangeStarts = 10;  % 交換法の初期配置の数（Python 版は30）
settings.sampling.exchangeMaxIterations = 300;
settings.sampling.constraints.radialZoneEdges = [0.45, 0.7];  % 同心円の区切り（Wafer 半径に対する比）
settings.sampling.constraints.quadrants = true;
settings.sampling.constraints.scanDirection = true;
settings.sampling.constraints.slack = 1;

% 比べる手法
settings.methods = alignest.recommendedMethods();

% 評価
settings.evaluation.outerRadiusRatio = 0.8;   % 外周とみなす半径（Wafer 半径に対する比）
settings.evaluation.removeLinear = false;     % 学習点の XY 1次（6項）を除いてから推定し、推定値に戻す
end
