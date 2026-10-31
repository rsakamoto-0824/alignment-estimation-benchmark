classdef AlignmentEstimationApp < appui.DataTab & appui.SettingsTab & appui.RunTab & appui.ResultsTab & ...
        appui.MapTab & appui.TargetTab & appui.HighOrderTab & appui.HighOrderCompareTab & appui.Display
    %ALIGNMENTESTIMATIONAPP アライメント計測値の面内推定を、実データ（Excel）で比べる画面。
    %   app = AlignmentEstimationApp();       画面を開く
    %   app = AlignmentEstimationApp(false);  画面を出さずに作る（自動テスト用）
    %   流れ：1. データの読み込み（列の対応・座標の単位・Wafer マップ・Shot レイアウト） → 2. 評価の設定 → 3. 実行
    %         （評価の後に条件を足して追加の評価もできる）→ 4. 結果一覧（表・グラフ・基準の手法との比較・推定値と誤差の
    %         分布・残差の箱ひげ図・散布図・分布の比較・処理時間の内訳。評価点を半径・Shot の条件で絞り込んで計算し直せる）
    %         → 5. Waferごとのマップ（1つの条件の計測値・推定値・残差、または複数の条件を並べて比べる）
    %         → 6. 未知の座標の推定（計測していない座標の推定と重ね合わせ補正値）
    %         → 7. Shot高次補正（計測値・推定値・Excel の値で、Shot 高次補正の k パラメータを VIF で選び、ロバスト回帰と
    %         高次項だけの L2 正則化で、Wafer 内で共通・Scan 方向ごと・行の偶奇ごと・Shot ごとに求めて、補正の効果を見る。
    %         くくり・λ・項の組み合わせを変えた補正をまとめて比べ、Wafer ごとの k パラメータ・残差も比べる）、8. ヘルプ
    %   計算は +alignest パッケージ（MATLAB 本体だけで動く）。画面はその呼び出しと表示だけを受け持つ。
    %
    %   ファイルの分け方（タブごとのファイル。どれも +appui フォルダ）：
    %     Core.m         共通：プロパティ・定数、起動の手順（startApp）、図の画像の保存・コピーなど
    %     DataTab.m      1. データの読み込み
    %     SettingsTab.m  2. 評価の設定
    %     RunTab.m       3. 実行（計測マップを含む）
    %     ResultsTab.m   4. 結果一覧
    %     MapTab.m       5. Waferごとのマップ
    %     TargetTab.m    6. 未知の座標の推定
    %     HighOrderTab.m 7. Shot高次補正（入力・補正の式・計算・補正の評価・補正値・マップ・書き出し）
    %     HighOrderCompareTab.m 7. Shot高次補正の補正の比較・Wafer の比較・項の組み合わせの保存
    %     Display.m      8. ヘルプと表示の設定（画面の色・文字の大きさ・凡例の位置・画面の大きさに合わせる）
    %     private/       いくつかのタブで使う小さな関数（画面の部品を作る・値を文字にするなど）

    methods
        function app = AlignmentEstimationApp(visible)
            if nargin < 1
                visible = true;
            end
            startApp(app, visible);
        end
    end
end
