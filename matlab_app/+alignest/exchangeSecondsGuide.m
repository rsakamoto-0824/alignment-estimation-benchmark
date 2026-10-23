function seconds = exchangeSecondsGuide(nShots, nStarts, nCandidates)
%EXCHANGESECONDSGUIDE 制約付き I 最適（交換法）で、1 Wafer の学習パターン1つを作る時間の目安 [秒]。
%   seconds = alignest.exchangeSecondsGuide(nShots, nStarts, nCandidates)   % nShots は並びでもよい（要素ごとの目安）
%   目安 = SECONDS_PER_SHOT_START × 学習 Shot 数 × 初期配置の数 × (候補 Shot 数 / REFERENCE_CANDIDATES)。
%   交換法は初期配置ごとに同じ計算をくり返すので、時間は初期配置の数にほぼ比例する。係数は、同梱の模擬データ
%   （候補 99 Shot・396 Mark、基準モデル XY 5次（21 項）、反復の上限 300）を MATLAB R2022b（Apple M1 の Mac、
%   Intel 版を Rosetta で実行）で測った値（2026-10-23）。初期配置 1〜100・学習 Shot 10〜40 で測り、初期配置 1 つあたり
%   学習 Shot 10 で約 0.08 秒、20 で 0.19 秒、30 で 0.29 秒、40 で 0.42 秒だった。PC の性能・データの大きさで変わる。
%   学習パターンは候補 Shot と Mark が同じ Wafer で使い回すので、評価全体では「配置の種類の数」倍になる。
SECONDS_PER_SHOT_START = 0.01;
REFERENCE_CANDIDATES = 99;
seconds = SECONDS_PER_SHOT_START * double(nShots) * double(nStarts) * double(nCandidates) / REFERENCE_CANDIDATES;
end
