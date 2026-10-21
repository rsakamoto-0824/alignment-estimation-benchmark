function [names, labels] = gprKernelChoices()
%GPRKERNELCHOICES 画面で選べる GPR のカーネル：fitrgp と同じ10種類と、ν を指定する Matérn（等方・ARD）。
%   matern・ardmatern は、設定の methods.gpr.maternNu の値ごとに matern_nu<ν>・ardmatern_nu<ν> に展開する。
fixed = alignest.models.gprKernelNames();
names = [fixed, "matern", "ardmatern"];
labels = [fixed, "matern（ν を指定）", "ardmatern（ν を指定）"];
end
