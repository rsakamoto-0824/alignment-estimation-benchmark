function checkRandomSeed(seed)
%CHECKRANDOMSEED 乱数の種が使える値（0〜2^32−1 の整数1つ）か確かめ、違えば止める。
%   alignest.checkRandomSeed(seed)
%   学習 Shot の選び方と「8. Mark配置の最適化」で共通の種（設定 sampling.seed）。メニュー「設定」→「乱数の種…」と、設定
%   ファイルの読み込みで確かめる（読んだ後に画面を作る途中で止まらないように）。
MAX_SEED = 2 ^ 32 - 1;
if ~isnumeric(seed) || ~isscalar(seed) || ~isfinite(seed) || seed ~= round(seed) || seed < 0 || seed > MAX_SEED
    error('alignest:randomSeed', '乱数の種は 0〜%d の整数にしてください。', MAX_SEED);
end
end
