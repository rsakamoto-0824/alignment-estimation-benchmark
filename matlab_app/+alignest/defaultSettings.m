function settings = defaultSettings()
%DEFAULTSETTINGS 初期設定。比べる手法はガウス過程回帰（GPR）だけ（alignest.recommendedMethods の "default"。
%   ほかの手法は画面の「推奨の組み合わせ」などで足せる）。
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
settings.factors.evaluateSingles = false;  % true なら、チェックした質的変数を1つだけ使う手法も足して比べる（alignest.singleFactorMethods）
settings.factors.separateY = false;      % true なら Y 成分は factors.y の質的変数を使う（false なら X と同じ）
settings.factors.y.scan = true;
settings.factors.y.mark = true;
settings.factors.y.shotRowParity = false;
settings.factors.y.columns = strings(1, 0);

% 学習に使う Shot の選び方
% 選び方（複数選ぶと、同じ評価の中で選び方どうしを比べる。alignest.buildPlanSpecs）：ioptimal（制約付き I 最適）／
% doptimal（制約付き D 最適）／random（制約つきランダム）／excel（Excel ファイルで指定：パターン・優先順。Mark 単位も）／
% mark（Mark 単位の I 最適）／markd（Mark 単位の D 最適）
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
settings.sampling.layoutPlans = strings(0, 1);   % Excel ファイルで指定した学習パターン（1行1パターン。alignest.readLayoutPlans・
                                                % parseLayoutPlans の "種類|名前|shotNo（shotNo-markNo）…"）
settings.sampling.layoutFile = "";               % 読み込んだ Excel ファイルの名前（表示・記録用）
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
                                        % （countBy = "rate" なら、代わりに計測率 = 候補の全 Mark に対する割合で決める）
settings.sampling.markRequirePerShot = true;   % Mark 単位：各 Shot で markMinPerShot 点以上を必ず計測する（false なら Shot を問わず選ぶ）
settings.sampling.markMinPerShot = 1;          % Mark 単位：各 Shot で必ず計測する Mark の数 n（Mark の少ない Shot はその Shot の全 Mark）

% 比べる手法
settings.methods = alignest.recommendedMethods("default");

% 評価
settings.evaluation.outerRadiusMm = 120;      % 外周とみなす Mark の半径 [mm]（この半径以上が外周。半径 150 mm の Wafer が前提）
settings.evaluation.removeLinear = false;     % 学習点の XY 1次（6項）を除いてから推定し、推定値に戻す
settings.evaluation.recordTiming = false;     % 条件（手法 × 学習パターン）ごとに 1 枚あたりの処理時間を記録して集計する
settings.evaluation.excludeOutliers = false;  % 学習データの異常値（中心から outlierSigma × ばらつき を超えて離れた Mark）を除いて推定する
settings.evaluation.outlierSigma = 3;         % 異常値とみなす倍数 n（正の値。ばらつきは Wafer・学習パターンごと）
settings.evaluation.outlierMethod = "sigma";  % 異常値の判定：sigma（平均と σ）・mad（中央値と 1.4826 × MAD）

% 表示（推定の結果は変えない。alignest.plot.scanStyle）
settings.display.scan1Up = true;                   % Scan 方向 1 を上向き（▲）にする。false なら 1 が下向き（▼）・2 が上向き（▲）
settings.display.scan1Color = [0.10, 0.58, 0.28];  % Scan 方向 1 の色（RGB 0〜1。既定は緑）
settings.display.scan2Color = [0.58, 0.20, 0.70];  % Scan 方向 2 の色（既定は紫）

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

% Shot 高次補正の評価（「7. Shot高次補正」のタブ。alignest.highOrderOptions。推定の評価には使わない）
settings.highOrder.maker = "nikon";        % 補正の式：asml（k1〜k19 の全項）・canon・nikon（Overlay 計測ルールの式）・
                                           % custom（カスタム：k1〜k38 から選ぶ）
settings.highOrder.unit = "common";        % k のくくり：common（Wafer 内の Shot で共通）・scan（Scan 方向ごと）・row（Shot 行の
                                           % 偶奇ごと）・shot（Shot ごと）
settings.highOrder.waferOrder = 1;         % Wafer 成分（Shot 中心の座標の多項式の次数。0〜5、0 = なし。shot のほかは k と一緒に、
                                           % shot は先に求めて引く）
settings.highOrder.excludedTerms = zeros(1, 0);  % 使わない k の番号（「VIF で選ぶ」・画面で外した項。k1〜k6 は外さない）
settings.highOrder.outerRadiusMm = 120;    % 外周の Shot（Shot 中心の半径がこの値 [mm] 以上）。内周・外周に分けた評価と外周の式に使う
settings.highOrder.outerMaker = "none";    % 外周の Shot の補正の式：none（分けない）・asml・canon・nikon・custom
settings.highOrder.outerExcludedTerms = zeros(1, 0);  % 外周の式で使わない k の番号（保存した項の組み合わせを選んだとき）
settings.highOrder.outerName = "";         % 外周の式に選んだ保存した項の組み合わせの名前（式の全項なら ""）
settings.highOrder.termSets = strings(0, 1);     % 保存した項の組み合わせ（1行 = "名前|式|k の番号 …"。画面の「組み合わせを保存」）
settings.highOrder.vifThreshold = 10;      % 「VIF で選ぶ」のしきい値（すべての項の VIF がこれより小さくなるまで高次項を外す）
settings.highOrder.loss = "huber";         % 回帰の損失関数：ols（最小二乗）・huber（Huber）・lad（最小絶対偏差）
settings.highOrder.huberTuning = 1.345;    % Huber の定数 c（正規分布の誤差で効率 95% になる値）
settings.highOrder.regularization = "l2";  % 正則化：none（なし）・l2（係数を小さくする）・l1（効かない項の係数を 0 にする）
settings.highOrder.penaltyOrders = 2:6;    % 正則化をかける項の次数（1〜6 から選ぶ。定数 k1・k2 と Wafer 成分にはかけない）
settings.highOrder.lambda = 0.1;           % 正則化の強さ λ（列を平均0・標準偏差1にそろえた係数に対して）
end
