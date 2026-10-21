function z = normalInverse(probability)
%NORMALINVERSE 標準正規分布の分位点 Φ⁻¹(p)。
z = -sqrt(2) * erfcinv(2 * probability);
end
