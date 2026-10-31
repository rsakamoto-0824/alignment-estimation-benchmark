function excluded = excludedFor(maker, used)
%EXCLUDEDFOR 使う項の k の番号から、使わない項（excludedTerms）を求める（k1〜k6 は外さない）
terms = alignest.highOrderTerms(maker);
excluded = reshape(terms.k(~terms.protected & ~ismember(terms.k, used)), 1, []);
end
