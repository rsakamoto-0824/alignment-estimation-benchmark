function [types, labels] = groupSelectionTypes(results)
%GROUPSELECTIONTYPES 学習パターンの列（results.groups）ごとの計測点の選び方（I 最適・D 最適・ランダムなど）。
%   [types, labels] = alignest.groupSelectionTypes(results)
%   types：選び方の名前（ioptimal・doptimal・random・sobol・poisson・file（Excel の優先順。以前のファイルの優先順）・
%   manual（Excel のパターン。以前の手動・人の選択）・mark・markd・markrandom・marksobol・markpoisson。分からなければ ""）、
%   labels：画面の名前（分からなければ「（不明）」）。どちらも results.groups と同じ並びの列ベクトル。
%   選び方は列の行の planType（評価した結果）から、無ければ列の名前の先頭（"I最適 20 Shot" など）から決める
%   （「計測配置の比較」・結果一覧のグラフ・補正の悪化で、選び方ごとに線を分けるのに使う）。
TYPES = ["ioptimal", "doptimal", "random", "sobol", "poisson", "file", "manual", "mark", "markd", "markrandom", ...
    "marksobol", "markpoisson"];
LABELS = ["I 最適", "D 最適", "ランダム", "Sobol 列", "ポアソンディスク", "Excel の優先順", "Excel のパターン", ...
    "Mark 単位の I 最適", "Mark 単位の D 最適", "Mark 単位のランダム", "Mark 単位の Sobol 列", "Mark 単位のポアソンディスク"];
PREFIXES = ["I最適", "D最適", "ランダム", "Sobol", "ポアソン", "優先順", "", "Mark最適", "MarkD最適", "Markランダム", ...
    "MarkSobol", "Markポアソン"];
groups = reshape(string(results.groups), [], 1);
types = strings(numel(groups), 1);
hasPlanType = any(string(results.table.Properties.VariableNames) == "planType");
for g = 1:numel(groups)
    first = find(results.table.group == groups(g), 1);
    if hasPlanType && ~isempty(first) && results.table.planType(first) ~= ""
        types(g) = results.table.planType(first);
    else
        types(g) = typeFromName(groups(g), results, PREFIXES, TYPES);
    end
end
[~, position] = ismember(types, TYPES);
labels = repmat("（不明）", numel(groups), 1);
labels(position > 0) = LABELS(position(position > 0));
end

function type = typeFromName(name, results, prefixes, types)
% 列の名前の先頭（選び方を比べたときの名前）から選び方を決める。無ければ設定の選び方（1つのとき）
type = "";
for k = 1:numel(prefixes)
    if prefixes(k) ~= "" && startsWith(name, prefixes(k) + " ")
        type = types(k);
        return
    end
end
methods = "";
if isfield(results, "settings") && isfield(results.settings, "sampling") && isfield(results.settings.sampling, "method")
    methods = string(results.settings.sampling.method);   % 読み込んだ結果などで設定が無いときは決めない
end
sweep = contains(name, " Shot") || contains(name, "計測率") || contains(name, "点/Shot");
if isscalar(methods) && methods ~= "excel" && methods ~= ""
    type = methods;
elseif any(methods == "excel") && sweep && ~contains(name, "（")
    type = "file";      % Excel の優先順（学習 Shot 数ごと）
elseif ~sweep || contains(name, "（")
    type = "manual";    % Excel のパターン（名前（12 Shot））
end
end
