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
settings.data.coordinateMode = "shotMark";  % 座標の定義：shotMark（Shot 中心 Xmm・Ymm ＋ Shot 内 markXmm・markYmm）・
                                            % absolute（Xmm・Ymm が点の Wafer 上の絶対座標。Shot 内の座標は無くてもよい）
settings.data.valueColumn = "";             % 推定する値：""（X・Y 成分 measX・measY）、または1変数にするファイルの列の名前
                                            % （膜厚・線幅など。中では X 成分として扱い、Y 成分は使わない。alignest.valueSpec）
settings.data.valueUnit = "nm";             % 1変数の単位（画面・Excel の表示だけに使う）
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
% 選び方（複数選ぶと、同じ評価の中で選び方どうしを比べる。alignest.buildPlanSpecs）：ioptimal（制約付き I 最適）／
% doptimal（制約付き D 最適）／random（制約つきランダム）／manual（手動・人の選択）／file（ファイルの優先順）／
% mark（Mark 単位の I 最適：全 Shot で1点以上）
settings.sampling.method = "ioptimal";
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
settings.sampling.constraints.radialZoneEdgesMm = [67.5, 105];  % 同心円の区切り：Shot 中心の半径 [mm]（半径 150 mm の Wafer が前提）
settings.sampling.constraints.quadrants = true;
settings.sampling.constraints.scanDirection = true;
settings.sampling.constraints.slack = 1;
settings.sampling.constraints.markRatio = true;   % Mark 単位：Mark 番号ごとの計測する数を全計測の割合にそろえる
settings.sampling.markPerShot = 1;      % Mark 単位：1 Shot あたりの平均の計測 Mark 数（1 = 全 Shot で1点。複数なら比べる）

% 比べる手法
settings.methods = alignest.recommendedMethods();

% 評価
settings.evaluation.outerRadiusMm = 120;      % 外周とみなす Mark の半径 [mm]（この半径以上が外周。半径 150 mm の Wafer が前提）
settings.evaluation.removeLinear = false;     % 学習点の XY 1次（6項）を除いてから推定し、推定値に戻す
settings.evaluation.recordTiming = false;     % 条件（手法 × 学習パターン）ごとに 1 枚あたりの処理時間を記録して集計する
settings.evaluation.excludeOutliers = false;  % 学習データの異常値（中心から outlierSigma × ばらつき を超えて離れた Mark）を除いて推定する
settings.evaluation.outlierSigma = 3;         % 異常値とみなす倍数 n（正の値。ばらつきは Wafer・学習パターンごと）
settings.evaluation.outlierMethod = "sigma";  % 異常値の判定：sigma（平均と σ）・mad（中央値と 1.4826 × MAD）

% Overlay 補正の評価（推定誤差で Overlay 残差がどれだけ増えるか。alignest.overlayChoice）。すべて「なし」なら評価しない
settings.overlay.waferOrder = 1;         % Wafer 成分：Shot 中心の座標の多項式の次数（0 = なし、1 = 並進・倍率・回転・直交度）
settings.overlay.shotCommon = "linear";  % Shot 共通成分：none・linear（k1〜k6）・asml・canon・nikon・formula（下の式）
settings.overlay.perShot = "none";       % Shot ごとの成分：none・translation（k1・k2）・linear（k1〜k6）・formula（下の式）
% 補正の式を入力するとき（alignest.parseCorrectionFormula）。Wafer 成分は waferUseFormula が true なら次数の代わりに使う。
% 式の x・y は、Wafer 成分では Shot 中心の座標、Shot 共通成分では Shot 内の座標。係数は最小二乗で求める
settings.overlay.waferUseFormula = false;
settings.overlay.waferFormula = struct("dx", "k1 + k3*x + k5*y", "dy", "k2 + k4*y + k6*x");
settings.overlay.shotFormula = struct("dx", "k1 + k3*x + k5*y", "dy", "k2 + k4*y + k6*x");
settings.overlay.perShotFormula = struct("dx", "k1 + k3*x + k5*y", "dy", "k2 + k4*y + k6*x");  % Shot ごとの成分の式（Shot 内の座標）
end
