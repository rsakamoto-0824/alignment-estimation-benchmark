function keep = independentColumns(design, tolerance)
%INDEPENDENTCOLUMNS 設計行列の列のうち、前の列で表せない列（論理の行ベクトル）。列の順に、それまでに残した列の正規直交
%   基底へ射影した残りの大きさで判定する（残りの割合が sqrt(tolerance) 以下の列は、前の列で表せる・決まらない列）。
%   keep = alignest.independentColumns(design, tolerance)
%   同じ射影を2回する（Gram–Schmidt の再直交化）ので、列が多くても数値的に安定。成分どうしで重なる項を前の項に
%   含める係数の求め方（alignest.targetOverlayCorrection・alignest.planComponentDifference）で使う。
nColumns = size(design, 2);
keep = false(1, nColumns);
basis = zeros(size(design, 1), 0);
for column = 1:nColumns
    vector = design(:, column);
    scale = norm(vector);
    if scale == 0
        continue
    end
    for pass = 1:2
        vector = vector - basis * (basis.' * vector);
    end
    remainder = norm(vector);
    if remainder > sqrt(tolerance) * scale
        keep(column) = true;
        basis(:, end + 1) = vector / remainder; %#ok<AGROW>
    end
end
end
