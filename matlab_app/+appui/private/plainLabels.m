function labels = plainLabels(labels)
% 画面に出す名前：末尾の（…）の補足を除く（補足はヘルプに書く）。（…）で始まる名前や補足の無い名前はそのまま
labels = string(labels);
hasNote = contains(labels, "（") & ~startsWith(labels, "（") & endsWith(labels, "）");
labels(hasNote) = extractBefore(labels(hasNote), "（");
end
