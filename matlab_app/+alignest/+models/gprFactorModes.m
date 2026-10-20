function [modes, labels] = gprFactorModes()
%GPRFACTORMODES GPR の質的変数（Scan方向・Mark番号・任意のShot行奇偶）の扱い方。
%   none         : 使わない（平均は定数）
%   basis        : 効果コードを平均の基底関数に加え、β と同時に推定する（固定効果。前回の「同時推定」）
%   backfit      : Backfitting（質的変数の効果と GPR を交互に当てはめ直す）
%   basis_int    : basis に Scan方向 × Mark番号 の交互作用の列を加える
%   additive     : 加法カーネル k = k_空間 + τ_s²[Scan方向が同じ] + τ_m²[Mark番号が同じ]（変量効果）
%   additive_int : additive に τ_sm²[Scan方向と Mark番号の両方が同じ] を加える
%   mixed        : 混合。Scan方向は基底関数（固定効果）、Mark番号は加法カーネル（変量効果）
%   mixed_int    : mixed に交互作用の項 τ_sm² を加える
%   Shot行奇偶を追加すると、basis/backfit は固定効果、additive は変量効果、mixed は固定効果。
%   *_int は有効な質的変数の全ペアの交互作用を含む。
modes = ["none", "basis", "backfit", "basis_int", "additive", "additive_int", "mixed", "mixed_int"];
labels = ["使わない", "同時推定（基底関数）", "Backfitting", "同時推定＋交互作用", ...
    "加法カーネル", "加法カーネル＋交互作用", "混合（Scan・行固定／Mark変量）", "混合＋交互作用"];
end
