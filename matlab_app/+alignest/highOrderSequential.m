function sequential = highOrderSequential(options)
%HIGHORDERSEQUENTIAL Shot 高次補正で、Shot 共通の k を先に引いて残りを k の組ごとに求めるか。
%   sequential = alignest.highOrderSequential(options)   % options：alignest.highOrderOptions の結果（settings.highOrder の形）
%   くくりが Shot ごと・Scan 方向ごと・行の偶奇ごと（Wafer 内で共通でない）で、Shot 共通の補正（options.shotCommon）が
%   "fit"（計算する）か "input"（値を入力）のとき true。Wafer 内で共通のくくりは k の組が Shot 共通そのものなので false。
GROUP_UNITS = ["shot", "scan", "row"];
sequential = any(string(options.unit) == GROUP_UNITS) && string(options.shotCommon) ~= "none";
end
