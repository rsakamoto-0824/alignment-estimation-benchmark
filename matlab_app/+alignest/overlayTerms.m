function terms = overlayTerms(model)
%OVERLAYTERMS Shot 内の補正式の項（係数番号と、Shot 内座標 x・y のべき）。
%   terms.dx・terms.dy は 項の数 × 3 の行列 [係数番号 k, x のべき, y のべき]。
%   model = "linear"：1次（k1〜k6：並進・倍率・回転・直交度）
%           "asml"・"canon"・"nikon"：Overlay 計測ルールの Shot 高次補正の式（項・係数番号・変数・符号は変えない）
%     ASML  dx = k1 + k3*x + k5*y + k7*x^2 + k11*y^2 + k13*x^3 + k19*y^3
%           dy = k2 + k4*y + k6*x + k8*y^2 + k10*x*y + k12*x^2 + k14*y^3 + k16*x*y^2
%     Canon dx = k1 + k3*x + k5*y + k9*x*y + k11*y^2 + k17*x*y^2 + k19*y^3 + k27*x*y^3
%           dy = k2 + k4*y + k6*x + k8*y^2 + k10*x*y + k14*y^3 + k16*x*y^2 + k24*x*y^3
%     Nikon dx = k1 + k3*x + k5*y + k7*x^2 + k9*x*y + k11*y^2 + k13*x^3 + k17*x*y^2 + k19*y^3 + k29*y^4 + k41*y^5 + k55*y^6
%           dy = k2 + k4*y + k6*x + k8*y^2 + k10*x*y + k12*x^2 + k14*y^3 + k16*x*y^2 + k18*x^2*y + k22*y^4
%                + k24*x*y^3 + k32*y^5 + k34*x*y^4 + k44*y^6 + k46*x*y^5
switch string(model)
    case "linear"
        terms.dx = [1, 0, 0; 3, 1, 0; 5, 0, 1];
        terms.dy = [2, 0, 0; 4, 0, 1; 6, 1, 0];
    case "asml"
        terms.dx = [1, 0, 0; 3, 1, 0; 5, 0, 1; 7, 2, 0; 11, 0, 2; 13, 3, 0; 19, 0, 3];
        terms.dy = [2, 0, 0; 4, 0, 1; 6, 1, 0; 8, 0, 2; 10, 1, 1; 12, 2, 0; 14, 0, 3; 16, 1, 2];
    case "canon"
        terms.dx = [1, 0, 0; 3, 1, 0; 5, 0, 1; 9, 1, 1; 11, 0, 2; 17, 1, 2; 19, 0, 3; 27, 1, 3];
        terms.dy = [2, 0, 0; 4, 0, 1; 6, 1, 0; 8, 0, 2; 10, 1, 1; 14, 0, 3; 16, 1, 2; 24, 1, 3];
    case "nikon"
        terms.dx = [1, 0, 0; 3, 1, 0; 5, 0, 1; 7, 2, 0; 9, 1, 1; 11, 0, 2; 13, 3, 0; 17, 1, 2; 19, 0, 3; ...
            29, 0, 4; 41, 0, 5; 55, 0, 6];
        terms.dy = [2, 0, 0; 4, 0, 1; 6, 1, 0; 8, 0, 2; 10, 1, 1; 12, 2, 0; 14, 0, 3; 16, 1, 2; 18, 2, 1; ...
            22, 0, 4; 24, 1, 3; 32, 0, 5; 34, 1, 4; 44, 0, 6; 46, 1, 5];
    otherwise
        error('alignest:overlayModel', 'Shot 内の補正式は linear・asml・canon・nikon のいずれかです: %s', model);
end
end
