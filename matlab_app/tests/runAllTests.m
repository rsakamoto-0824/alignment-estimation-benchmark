function results = runAllTests()
%RUNALLTESTS 自動テストをすべて実行し、結果の一覧を表示する。
%   MATLAB で matlab_app フォルダを開き、runAllTests と入力する（tests フォルダをパスに加える）。
%   TestPythonReference は Python 版の計算結果（reference/python_reference.json）と照合する。
here = fileparts(mfilename('fullpath'));
addpath(fileparts(here));
addpath(here);
results = runtests(here);
disp(table(results));
fprintf('成功 %d 件、失敗 %d 件、未完了 %d 件\n', nnz([results.Passed]), nnz([results.Failed]), nnz([results.Incomplete]));
end
