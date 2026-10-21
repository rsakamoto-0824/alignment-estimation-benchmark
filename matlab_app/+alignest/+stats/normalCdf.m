function probability = normalCdf(z)
%NORMALCDF 標準正規分布の累積分布関数 Φ(z)。裾でも桁落ちしないよう erfc で求める。
probability = 0.5 * erfc(-z / sqrt(2));
end
