function used = usesFactors(method)
%USESFACTORS 手法が質的変数（Scan 方向・Mark 番号・Shot 行の奇偶・その他の列）を使うか。
%   GPR・TPS・RBF・Kriging・Fringe Zernike・GAM は質的変数の扱いが「なし」以外のとき使う（GPR の同時推定・加法カーネル、
%   GAM は効果コードの項、ほかは Backfitting）。XY 多項式・RT モデルは使わない。
used = any(method.family == ["GPR", "TPS", "RBF", "OK", "UK", "FZ", "GAM"]) && method.factorMode ~= "none";
end
