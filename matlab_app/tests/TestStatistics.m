classdef TestStatistics < matlab.unittest.TestCase
    %TESTSTATISTICS 正規性検定・ANOVA・百分位点を SciPy・NumPy の計算結果と照合する。
    %   基準値は、同じ式で作ったデータ（x_i = sin(1.7 i) + 0.25 cos(0.37 i²)、skew はその exp）を
    %   scipy.stats.shapiro・anderson・jarque_bera・f_oneway、numpy.percentile（SciPy 1.18.1・NumPy 2.5.4）で求めた値。

    properties (Constant)
        % 種類, n, Shapiro–Wilk W, p, Anderson–Darling A², Jarque–Bera, p
        REFERENCE = {
            "base", 3, 0.984596488675435, 0.762352889439191, NaN, 0.314498910564742, 0.854490874966373
            "base", 4, 0.965328671820366, 0.812377621224606, NaN, 0.387300938168562, 0.823945848489867
            "base", 5, 0.945920958217029, 0.70804115981394, NaN, 0.465904965847062, 0.792191215240547
            "base", 7, 0.958603834806393, 0.806670729533909, NaN, 0.422861941118704, 0.809425153289867
            "base", 11, 0.971659426658194, 0.902769549169228, 0.178402073351457, 0.607692988414059, 0.73797414106193
            "base", 12, 0.957848715032636, 0.752735369402717, 0.259671444651957, 0.758070967081257, 0.684521322995163
            "base", 30, 0.947896815237859, 0.148455194538711, 0.448164808192502, 1.8593271171993, 0.394686476907259
            "base", 200, 0.951061104983605, 2.39119498231827e-06, 2.80795489738784, 12.7947482622155, 0.00166592603812199
            "base", 4000, 0.942387575999203, 6.4595607543997e-37, 70.9800090012691, 293.661406315295, 1.70700913274627e-64
            "skew", 3, 0.863666302359161, 0.277720675343745, NaN, 0.486615627754676, 0.784030141266826
            "skew", 7, 0.871156298670443, 0.189995443041802, NaN, 0.985712999586852, 0.610878924028271
            "skew", 30, 0.893555226358119, 0.00586345700690035, 1.07250726702472, 3.13456970916554, 0.208610822831052
            "skew", 4000, 0.892890767482795, 2.10768257849364e-46, 145.333385892041, 421.775378029557, 2.58607049615838e-92
            }
    end

    methods (TestClassSetup)
        function addAppPath(~)
            addpath(fileparts(fileparts(mfilename('fullpath'))));
        end
    end

    methods (Test)
        function normalityTestsMatchSciPy(testCase)
            for k = 1:size(testCase.REFERENCE, 1)
                [kind, n, w, p, a2, jb, jbP] = testCase.REFERENCE{k, :};
                x = sample(n, kind);
                name = sprintf("%s n=%d", kind, n);
                result = alignest.stats.normalityTests(x);
                testCase.verifyEqual(result.swW, w, 'RelTol', 1e-10, name);
                testCase.verifyEqual(result.swP, p, 'RelTol', 1e-8, name);
                testCase.verifyEqual(result.jb, jb, 'RelTol', 1e-10, name);
                testCase.verifyEqual(result.jbP, jbP, 'RelTol', 1e-8, name);
                if isnan(a2)
                    testCase.verifyTrue(isnan(result.adA2), name);
                else
                    testCase.verifyEqual(result.adA2, a2, 'RelTol', 1e-10, name);
                end
            end
        end

        function andersonDarlingPValueFollowsStephens(testCase)
            % p 値の近似式（D'Agostino & Stephens 1986）を区間ごとに確かめる
            x = sample(30, "base");
            [a2, p] = alignest.stats.andersonDarling(x);
            adjusted = a2 * (1 + 0.75 / 30 + 2.25 / 30 ^ 2);
            testCase.verifyEqual(p, exp(0.9177 - 4.279 * adjusted - 1.38 * adjusted ^ 2), 'RelTol', 1e-12);
            [a2, p] = alignest.stats.andersonDarling(sample(200, "base"));
            adjusted = a2 * (1 + 0.75 / 200 + 2.25 / 200 ^ 2);
            testCase.verifyEqual(p, exp(1.2937 - 5.709 * adjusted + 0.0186 * adjusted ^ 2), 'RelTol', 1e-12);
        end

        function shapiroWilkIsSkippedOutsideItsRange(testCase)
            [w, p] = alignest.stats.shapiroWilk(sample(5001, "base"));
            testCase.verifyTrue(isnan(w) && isnan(p));
            [w, p] = alignest.stats.shapiroWilk(ones(10, 1));
            testCase.verifyTrue(isnan(w) && isnan(p));
            result = alignest.stats.normalityTests([1; NaN; 2]);
            testCase.verifyEqual(result.n, 2);
            testCase.verifyTrue(isnan(result.swP));
        end

        function oneWayAnovaMatchesSciPyAndAdjustsForOtherFactors(testCase)
            i = (1:30).';
            x = sample(30, "base") + 0.4 * (mod(i, 3) == 0);
            groups = struct("name", "群", "levels", string(mod(i, 3)));
            result = alignest.stats.anovaMainEffects(x, groups);
            testCase.verifyEqual(result.F, 1.0597454091462786, 'RelTol', 1e-10);
            testCase.verifyEqual(result.p, 0.3605203892037832, 'RelTol', 1e-10);
            testCase.verifyEqual([result.df1, result.df2], [2, 27]);
            % 1つの変数だけなら、調整した検定は一元配置と同じ
            testCase.verifyEqual(result.adjustedF, result.F, 'RelTol', 1e-10);
            % 同じ分け方の変数は区別できない。水準が1つの変数・値の無い点は使わない
            factors = [groups, struct("name", "同じ", "levels", "g" + string(mod(i, 3))), ...
                struct("name", "一定", "levels", repmat("A", 30, 1))];
            x(1) = NaN;
            result = alignest.stats.anovaMainEffects(x, factors);
            testCase.verifyEqual(result.adjustedDf(1:2), [0; 0]);
            testCase.verifyTrue(all(isnan(result.adjustedP(1:2))));
            testCase.verifyTrue(all(contains(result.note(1:2), "同じ分け方")));
            testCase.verifyEqual(result.note(3), "水準が1つしかないので検定しません。");
            testCase.verifyEqual(result.df2(1), 26);
            % 効果がはっきりしている変数は小さい p 値になり、関係の無い変数で調整しても残る
            effect = 5 * (mod(i, 2) == 0) + 0.1 * sample(30, "base");
            factors = [struct("name", "効果あり", "levels", string(mod(i, 2))), ...
                struct("name", "効果なし", "levels", string(mod(floor((i - 1) / 2), 3)))];
            result = alignest.stats.anovaMainEffects(effect, factors);
            testCase.verifyLessThan(result.p(1), 1e-10);
            testCase.verifyLessThan(result.adjustedP(1), 1e-10);
            testCase.verifyTrue(startsWith(result.levelSummary(1), "0: ") && contains(result.levelSummary(1), "（15 点）"));
        end

        function percentileMatchesNumPy(testCase)
            x = sample(30, "base");
            testCase.verifyEqual(alignest.stats.percentile(x, 95), 1.1500727042284173, 'RelTol', 1e-12);
            testCase.verifyEqual(alignest.stats.percentile(x, 50), median(x), 'RelTol', 1e-12);
            testCase.verifyEqual(alignest.stats.percentile(sample(7, "base"), 5), -0.9752450853677694, 'RelTol', 1e-12);
            testCase.verifyEqual(alignest.stats.percentile([NaN; 2; 4], 50), 3);
            testCase.verifyTrue(isnan(alignest.stats.percentile(NaN(3, 1), 95)));
        end
    end
end

function x = sample(n, kind)
i = (1:n).';
x = sin(1.7 * i) + 0.25 * cos(0.37 * i .^ 2);
if kind == "skew"
    x = exp(x);
end
end
