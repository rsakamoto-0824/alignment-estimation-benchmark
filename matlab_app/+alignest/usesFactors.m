function used = usesFactors(method)
%USESFACTORS 手法が質的変数（Scan 方向・Mark 番号・Shot 行の奇偶・その他の列）を使うか。
%   GAM は常に使う。GPR・TPS・RBF・Kriging・Fringe Zernike は質的変数の扱いが「なし」以外のとき使う
%   （GPR の同時推定・加法カーネル・混合、ほかは Backfitting）。XY 多項式・RT モデルは使わない。
used = method.family == "GAM" || ...
    (any(method.family == ["GPR", "TPS", "RBF", "OK", "UK", "FZ"]) && method.factorMode ~= "none");
end
