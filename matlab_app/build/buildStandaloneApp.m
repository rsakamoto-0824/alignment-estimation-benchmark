function results = buildStandaloneApp(options)
%BUILDSTANDALONEAPP スタンドアローンのアプリを作る（Windows では .exe）。MATLAB Compiler が必要。
%   使い方（MATLAB で matlab_app フォルダを開いて）
%       addpath build
%       buildStandaloneApp                         % 実行ファイルだけ作る（Pro 版）
%       buildStandaloneApp(edition="standard")     % 通常版（比べる手法・計測点の選び方・Overlay の式を絞った版）を作る
%       buildStandaloneApp(makeInstaller=true)     % インストーラーも作る（MATLAB Runtime をネットから入れる形）
%       buildStandaloneApp(makeInstaller=true, runtimeDelivery="installer")
%                                                  % インストーラーに MATLAB Runtime を入れる（ネットに出られない PC 用。数 GB になる）
%   出力は build/output/<OS の種類>/<版>/（版は pro・standard）。Windows では画面だけのアプリ（コマンド画面を出さない）
%   として作る。Pro 版は AlignmentEstimationApp、通常版は AlignmentEstimationAppStandard という名前の実行ファイルになる
%   （入口は runAlignmentEstimationApp・runAlignmentEstimationAppStandard）。
%   使う PC には、作った MATLAB と同じ版の MATLAB Runtime（無料）が必要（インストーラーを使うと一緒に入る）。
%   MATLAB 本体だけで動く作りなので、ほかの Toolbox は不要。
arguments
    options.makeInstaller (1, 1) logical = false
    options.outputFolder (1, 1) string = ""
    options.runtimeDelivery (1, 1) string {mustBeMember(options.runtimeDelivery, ["web", "installer"])} = "web"
    options.edition (1, 1) string {mustBeMember(options.edition, ["pro", "standard"])} = "pro"
end
APP_NAME = "AlignmentEstimationApp";
DISPLAY_NAME = "面内推定評価ツール";
MAIN_FILE = "runAlignmentEstimationApp.m";
if options.edition == "standard"
    APP_NAME = APP_NAME + "Standard";
    DISPLAY_NAME = DISPLAY_NAME + "（通常版）";
    MAIN_FILE = "runAlignmentEstimationAppStandard.m";
end
APP_VERSION = "1.0.0";
root = fileparts(fileparts(mfilename('fullpath')));
if ~license('test', 'Compiler') || isempty(which('compiler.build.standaloneApplication'))
    error('alignest:noCompiler', ['MATLAB Compiler が使えません（ライセンスまたはインストールがありません）。' ...
        'MATLAB Compiler の入った PC で実行してください。MATLAB の中で使うだけなら runAlignmentEstimationApp で起動できます。']);
end
outputFolder = options.outputFolder;
if outputFolder == ""
    outputFolder = fullfile(root, "build", "output", computer('arch'), options.edition);
end
mainFile = fullfile(root, MAIN_FILE);
additionalFiles = {fullfile(root, "AlignmentEstimationApp.m"), fullfile(root, "+appui"), fullfile(root, "+alignest"), ...
    fullfile(root, "help")};   % 画面はタブごとのファイル（+appui）に分けてある
fprintf('作成を始めます：%s（数分かかります）\n', outputFolder);
if ispc
    results = compiler.build.standaloneWindowsApplication(mainFile, 'ExecutableName', APP_NAME, ...
        'ExecutableVersion', APP_VERSION, 'AdditionalFiles', additionalFiles, 'OutputDir', outputFolder, 'Verbose', 'on');
else
    results = compiler.build.standaloneApplication(mainFile, 'ExecutableName', APP_NAME, ...
        'AdditionalFiles', additionalFiles, 'OutputDir', outputFolder, 'Verbose', 'on');
end
fprintf('作成しました：%s\n', strjoin(string(results.Files), newline));
if options.makeInstaller
    installerFolder = fullfile(outputFolder, "installer");
    compiler.package.installer(results, 'InstallerName', APP_NAME + "_Installer", 'Version', APP_VERSION, ...
        'ApplicationName', DISPLAY_NAME, 'RuntimeDelivery', options.runtimeDelivery, ...
        'OutputDir', installerFolder);
    fprintf('インストーラーを作りました：%s\n', installerFolder);
end
end
