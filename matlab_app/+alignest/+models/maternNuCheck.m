function maternNuCheck(nu)
%MATERNNUCHECK Matérn カーネルの ν（滑らかさを決める次数）が使える値かを確かめる。
%   ν が大きいほど滑らか（ν = 0.5 は exponential、ν → ∞ で squaredexponential に近づく）。
%   計算できる範囲として 0 < ν ≤ 50 とする。
MAX_NU = 50;
if ~isscalar(nu) || ~isfinite(nu) || nu <= 0 || nu > MAX_NU
    error('alignest:maternNu', 'Matérn の ν は 0 より大きく %g 以下の数にしてください: %s', MAX_NU, string(nu));
end
end
