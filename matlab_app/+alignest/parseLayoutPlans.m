function plans = parseLayoutPlans(lines)
%PARSELAYOUTPLANS 「Excel ファイルで指定」の学習パターン（設定 sampling.layoutPlans の行）を読む。
%   plans = alignest.parseLayoutPlans(lines)
%   1行が1パターン："種類|名前|項目 項目 …"（alignest.readLayoutPlans が作る）。
%   種類：pattern（計測する Shot・Mark の組）・priority（計測する順。学習 Shot 数・計測率ごとに先頭から使う）。
%   項目：Shot 単位は shotNo（例：12）、Mark 単位は shotNo-markNo（例：12-3）。priority の項目は計測する順に並べ、
%   先頭に「!」の付いた項目は必ず計測する（学習 Shot 数より多くても使う。Excel の優先順の列で 1 の行）。
%   plans：構造体の配列。kind・name・shotNos（列）・markNos（列。Shot 単位は空）・required（列。必ず計測する項目）。
arguments
    lines string
end
plans = struct("kind", {}, "name", {}, "shotNos", {}, "markNos", {}, "required", {});
lines = strtrim(lines(:));
lines = lines(strlength(lines) > 0);
for k = 1:numel(lines)
    parts = split(lines(k), "|");
    if numel(parts) ~= 3 || ~any(parts(1) == ["pattern", "priority"])
        error('alignest:layoutPlans', 'Excel で指定した学習パターンの %d 行目の形が正しくありません: %s', k, lines(k));
    end
    items = split(strtrim(parts(3)));
    items = items(strlength(items) > 0);
    required = startsWith(items, "!");
    items = erase(items, "!");
    pairs = split(items, "-", 2);
    if isvector(pairs) && numel(items) == 1
        pairs = reshape(pairs, 1, []);
    end
    markLevel = all(contains(items, "-")) && ~isempty(items);
    if markLevel
        shotNos = str2double(pairs(:, 1));
        markNos = str2double(pairs(:, 2));
    else
        shotNos = str2double(items);
        markNos = zeros(0, 1);
    end
    if isempty(shotNos) || any(~isfinite(shotNos)) || (markLevel && any(~isfinite(markNos))) || ...
            (~markLevel && any(contains(items, "-")))
        error('alignest:layoutPlans', 'Excel で指定した学習パターン「%s」の shotNo（markNo）が読めません。', parts(2));
    end
    plans(end + 1) = struct("kind", parts(1), "name", strtrim(parts(2)), "shotNos", shotNos(:), "markNos", ...
        markNos(:), "required", required(:)); %#ok<AGROW>
end
names = string({plans.name});
if numel(unique(names)) < numel(names)
    error('alignest:layoutPlans', 'Excel で指定した学習パターンに同じ名前があります。列の見出しを変えてください。');
end
end
