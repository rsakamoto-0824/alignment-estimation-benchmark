function [names, labels] = directionRules()
%DIRECTIONRULES Scan 方向（Direction）が無い行に付ける規則の名前と、画面に出す説明。
%   serpentine  ：一筆書き。shotNo が最も小さい Shot を 1（+1 方向）として、その行を端から端へ、次の行は逆向きに
%                 たどる道順（行ごとに折り返す）で Shot を繋ぎ、道順に 1・2 を交互に付ける（初期設定）
%   shotNoParity：shotNo の奇数を 1、偶数を 2（露光の順に Scan 方向が交互に変わり、shotNo が露光順の場合）
%   checkerboard：Shot 行と Shot 列の番号の和の奇偶（上の行・左の列の Shot を 1）
%   rowParity   ：Shot 行の奇偶（上から1行目を 1）
%   columnParity：Shot 列の奇偶（左から1列目を 1）
%   行・列は Wafer・測定日時ごとに、入力の Shot 中心座標（半径・入力行の除外前）から数える。
names = ["none", "serpentine", "shotNoParity", "checkerboard", "rowParity", "columnParity"];
labels = ["付けない（Scan 方向を使わない）", "一筆書き（最小の shotNo を 1 として、行ごとに折り返す道順で交互）", ...
    "shotNo の奇数 = 1・偶数 = 2（露光順に交互）", ...
    "市松模様（上の行・左の列の Shot = 1）", "Shot 行ごとに交互（上から1行目 = 1）", ...
    "Shot 列ごとに交互（左から1列目 = 1）"];
end
