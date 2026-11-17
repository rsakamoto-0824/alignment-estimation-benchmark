function options = highOrderSharedFormula(options)
%HIGHORDERSHAREDFORMULA くくりが Wafer 内で共通・選択 Wafer で共通のとき、k の組に使う補正の式と項を、「Shot 共通補正」の
%   欄の設定（Shot 共通の補正の式・Shot 共通の項）にする。
%   options = alignest.highOrderSharedFormula(options)   % options：alignest.highOrderOptions の結果
%   この2つのくくりでは、k の組が Shot 共通補正そのもの（Wafer 内・選んだ Wafer のすべての Shot で共通の k）なので、
%   補正の式と使う項は「Shot 共通補正」の欄で選ぶ（「Shot ごとの補正」の欄は使わない）。返す options は、その式と項を
%   maker・excludedTerms（外周の式を分けるときは outerMaker・outerExcludedTerms）に入れたもの（alignest.shotHighOrder は
%   これを使う）。Shot 共通を先に引くときの求め方（alignest.shotHighOrder の Shot 共通の k）と同じ決め方：
%   - shotCommonMaker が "same"（Shot ごとと同じ）：式は maker（外周は outerMaker）のまま。shotCommonTerms
%     （外周は shotCommonOuterTerms）が空なら使う項（excludedTerms で外した項を除く）、空でなければその k の項（k1〜k6 は必ず使う）
%   - ほかの式：その式（外周の式を分けるときも同じ式）。shotCommonTerms（外周は shotCommonOuterTerms）が空ならその式の
%     すべての項、空でなければその k の項
%   返す options の shotCommonMaker は "same"、shotCommonTerms・shotCommonOuterTerms は空にする（式と項は maker・
%   excludedTerms に入れた）。説明（description）も作り直す。ほかのくくりでは options をそのまま返す。
SHARED_UNITS = ["common", "wafers"];
if ~any(options.unit == SHARED_UNITS)
    return
end
split = options.outerMaker ~= "none";
lists = {options.shotCommonTerms, options.shotCommonOuterTerms};
excludedFields = ["excludedTerms", "outerExcludedTerms"];
makerFields = ["maker", "outerMaker"];
if options.shotCommonMaker ~= "same"
    options.maker = options.shotCommonMaker;
    if split
        options.outerMaker = options.shotCommonMaker;   % 外周の式を分けるときも同じ式（k の組は内周・外周で別）
        options.outerName = "";
    end
    for z = 1:1 + split
        options.(excludedFields(z)) = zeros(1, 0);   % 項を選んでいなければ、その式のすべての項
    end
end
for z = 1:1 + split
    if ~isempty(lists{z})
        terms = alignest.highOrderTerms(options.(makerFields(z)));
        options.(excludedFields(z)) = reshape(setdiff(terms.k, lists{z}), 1, []);   % k1〜k6 は外しても使う
        if z == 2
            options.outerName = "";
        end
    end
end
options.shotCommonMaker = "same";
options.shotCommonTerms = zeros(1, 0);
options.shotCommonOuterTerms = zeros(1, 0);
options.description = alignest.highOrderOptions(struct("highOrder", options)).description;
end
