classdef AlignmentEstimationApp < appui.DataTab & appui.SettingsTab & appui.RunTab & appui.ResultsTab & ...
        appui.MapTab & appui.TargetTab & appui.HighOrderTab & appui.HighOrderCompareTab & appui.HighOrderAnalysisTab & ...
        appui.HighOrderSweepTab & appui.HighOrderHistoryTab & appui.MarkLayoutTab & appui.RotationTab & appui.Display
    %ALIGNMENTESTIMATIONAPP アライメント計測値の面内推定を、実データ（Excel）で比べる画面。
    %   app = AlignmentEstimationApp();       画面を開く
    %   app = AlignmentEstimationApp(false);  画面を出さずに作る（自動テスト用）
    %   app = AlignmentEstimationApp(visible, lazyTabs)  lazyTabs = true なら「3. 結果一覧」から後のタブを初めて開いたときに
    %         作る（起動が速い。画面を出すときの既定）。false なら起動のときにすべて作る（画面を出さないときの既定）
    %   app = AlignmentEstimationApp(visible, lazyTabs, edition)  edition："pro"（Pro 版。既定）・"standard"（通常版。
    %         比べる手法は GPR・TPS・XY 多項式、計測点の選び方は Shot 単位の I 最適・ランダム、Overlay 補正は組み込みの式だけ。
    %         設定の欄が少ないので起動が速い。alignest.editionSettings）
    %   流れ：1. データ読込（列の対応・座標の単位・Wafer マップ・Shot レイアウト） → 2. 評価の設定 → 3. 実行
    %         （評価の後に条件を足して追加の評価もできる）→ 4. 結果一覧（表・グラフ・基準の手法との比較・推定値と誤差の
    %         分布・残差の箱ひげ図・散布図・分布の比較・処理時間の内訳。評価点を半径・Shot の条件で絞り込んで計算し直せる）
    %         → 5. Waferごとのマップ（1つの条件の計測値・推定値・残差、または複数の条件を並べて比べる）
    %         → 6. 未知の座標の推定（計測していない座標の推定と重ね合わせ補正値）
    %         → 7. Shot高次補正（計測値・推定値・Excel の値で、Shot 高次補正の k パラメータを VIF で選び、ロバスト回帰と
    %         高次項だけの L2 正則化で、Wafer 内で共通・Scan 方向ごと・行の偶奇ごと・Shot ごとに求めて、補正の効果を見る。
    %         外周の Shot だけ別の式にでき、内周・外周に分けて評価する。くくり・λ・回帰・項の組み合わせを変えた補正を
    %         まとめて比べ、2つの条件の Wafer を並べて改善・悪化した Shot を見る。Wafer ごとの k パラメータ・残差、
    %         残差のヒストグラムも見る。λ・c をスイープして補正残差の推移から選ぶ）
    %         → 8. Mark配置の最適化（Shot 高次補正の計測 Mark の配置を、Mark の数ごとに I 最適計画で選び、補正した制御残差を
    %         I 効率と比べる。実測値の無い座標は乱数 Shot で評価する）
    %         → 9. 計測マップのローテーション（Shot・Mark ごとのばらつき（3σ）で計測の優先度を分け、ローテーションする計測
    %         マップを作り、FB 側の Wafer で求めた補正値を検証側の Wafer に当てた補正残差で条件を比べる）。ヘルプはメニューから
    %         別の窓で開く
    %   計算は +alignest パッケージ（MATLAB 本体だけで動く）。画面はその呼び出しと表示だけを受け持つ。
    %
    %   ファイルの分け方（タブごとのファイル。どれも +appui フォルダ）：
    %     Core.m         共通：プロパティ・定数、起動の手順（startApp）、図の画像の保存・コピーなど
    %     DataTab.m      1. データ読込
    %     SettingsTab.m  2. 評価の設定
    %     RunTab.m       3. 実行（計測マップを含む）
    %     ResultsTab.m   4. 結果一覧
    %     MapTab.m       5. Waferごとのマップ
    %     TargetTab.m    6. 未知の座標の推定
    %     HighOrderTab.m 7. Shot高次補正（入力・補正の式・計算・補正の評価・補正値・マップ・書き出し）
    %     HighOrderCompareTab.m 7. Shot高次補正の補正の比較・2つの条件を並べる・Wafer の比較・項の組み合わせの保存
    %     HighOrderAnalysisTab.m 7. Shot高次補正のヒストグラム
    %     HighOrderSweepTab.m 7. Shot高次補正の λ・c のスイープ（補正残差の推移と、最もよい値）
    %     MarkLayoutTab.m 8. Mark配置の最適化（入力・候補の Mark・補正の式・回帰・乱数 Shot 生成・制御残差と I 効率・配置）
    %     RotationTab.m  9. 計測マップのローテーション（ばらつき・優先度と計測マップ・FB の検証・条件の比較・書き出し）
    %     ProgressWindow.m 計算中の進み具合の窓（文の行数に合わせて高さを変える）
    %     Display.m      メニュー「ヘルプ」と表示の設定（画面の色・文字の大きさ・凡例の位置・画面の大きさに合わせる）
    %     private/       いくつかのタブで使う小さな関数（画面の部品を作る・値を文字にするなど）

    methods
        function app = AlignmentEstimationApp(visible, lazyTabs, edition)
            if nargin < 1
                visible = true;
            end
            if nargin < 2
                lazyTabs = visible;
            end
            if nargin < 3
                edition = "pro";
            end
            edition = string(edition);
            if ~(isscalar(edition) && any(edition == ["pro", "standard"]))
                error('alignest:edition', '版は "pro"（Pro 版）か "standard"（通常版）です: %s', join(edition, "・"));
            end
            startApp(app, logical(visible), logical(lazyTabs), edition);
        end
    end
end
