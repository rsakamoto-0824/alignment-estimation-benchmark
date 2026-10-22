function settings = defaultSettings()
%DEFAULTSETTINGS 初期設定。比べる手法は「推奨の組み合わせ」（前回の模擬データの評価で各系統の代表になった設定）。
settings.version = 1;

% データ（Overlay 計測ルール：300 mm Wafer、有効な点は r < 150 mm）
settings.data.waferRadiusMm = 150;      % 座標を割って単位をそろえる値（説明変数・基底関数）
settings.data.validRadiusMm = 150;      % この半径以上の点は除く
settings.data.coordinateUnits = alignest.coordinateUnits();
settings.data.excludeZeroMeasurements = false; % measX・measY がともに0の入力行を除く
settings.data.excludeUnmeasuredRecords = false; % StsX・StsY のどちらかが−1の入力行を除く
settings.data.directionRule = "serpentine";  % Direction が無い行に Scan 方向を付ける規則（alignest.directionRules。一筆書き）
settings.data.invertDirection = false;  % 規則で付ける 1 と 2 を入れ替える
settings.data.directionOverrideShots = zeros(1, 0);   % 画面で Scan 方向を変えた shotNo（すべての Wafer に当てる）
settings.data.directionOverrideValues = zeros(1, 0);  % その Scan 方向（1・2。shotNo と同じ順）
% 質的変数（GPR・GAM・TPS／RBF／Kriging の Backfitting で使う）
settings.factors.scan = true;           % Scan 方向（Direction）
settings.factors.mark = true;           % Mark 番号（markNo）
settings.factors.shotRowParity = false; % Shot 配列の行（上から1行目）の奇数・偶数
settings.factors.columns = strings(1, 0);  % ファイルのその他の列（標準の項目に対応づけなかった列）の名前
settings.factors.separateY = false;      % true なら Y 成分は factors.y の質的変数を使う（false なら X と同じ）
settings.factors.y.scan = true;
settings.factors.y.mark = true;
settings.factors.y.shotRowParity = false;
settings.factors.y.columns = strings(1, 0);

% 学習に使う Shot の選び方
settings.sampling.method = "ioptimal";  % ioptimal（制約付き I 最適）／random（制約つきランダム）／manual（手動）／file（ファイルの優先順）
settings.sampling.nShotsStart = 10;     % 学習 Shot 数は 開始・終了・刻み で決める（I 最適・ランダム）
settings.sampling.nShotsEnd = 40;
settings.sampling.nShotsStep = 5;
settings.sampling.nShots = alignest.shotCountList(10, 40, 5);  % 開始・終了・刻みから作った並び（計算はこれを使う）
settings.sampling.countBy = "shots";    % 学習 Shot 数の決め方：shots（Shot 数）／rate（計測率 [%]。Wafer の候補 Shot 数に対する割合）
settings.sampling.rateStart = 10;       % 計測率 [%] の開始・終了・刻み（countBy = "rate" のとき。alignest.measurementRateList）
settings.sampling.rateEnd = 40;
settings.sampling.rateStep = 10;
settings.sampling.randomRepeats = 10;
settings.sampling.seed = 20261017;
settings.sampling.manualPlans = strings(0, 1);
settings.sampling.priorityShots = zeros(1, 0);   % 優先順のファイルの Shot 番号（行の順。alignest.readShotPriority）
settings.sampling.priorityLevels = zeros(1, 0);  % 同じく優先度（0 = 計測しない、1 = 必ず計測する、それ以外・NaN = 行の順）
settings.sampling.priorityFile = "";             % 読み込んだファイルの名前（表示・記録用）
settings.sampling.requiredShots = zeros(1, 0);   % 必ず計測する shotNo（I 最適・ランダム。拡張 I 最適計画）
settings.sampling.requireOuterShots = false;     % 最外周の Shot（alignest.outerShots）をすべて必ず計測する
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
settings.evaluation.recordTiming = false;     % 条件（手法 × 学習パターン）ごとに 1 枚あたりの処理時間を記録して集計する
settings.evaluation.excludeOutliers = false;  % 学習データの異常値（平均から outlierSigma × σ を超えて離れた Mark）を除いて推定する
settings.evaluation.outlierSigma = 3;         % 異常値とみなす σ の倍数 n（正の値。σ は Wafer・学習パターンごと）

% Overlay 補正の評価（推定誤差で Overlay 残差がどれだけ増えるか。alignest.overlayChoice）。すべて「なし」なら評価しない
settings.overlay.waferOrder = 1;         % Wafer 成分：Shot 中心の座標の多項式の次数（0 = なし、1 = 並進・倍率・回転・直交度）
settings.overlay.shotCommon = "linear";  % Shot 共通成分：none・linear（k1〜k6）・asml・canon・nikon
settings.overlay.perShot = "none";       % Shot ごとの成分：none・translation（k1・k2）・linear（k1〜k6）
end
