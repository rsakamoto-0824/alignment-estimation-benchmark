function [names, labels] = gprKernelChoices()
%GPRKERNELCHOICES 画面で選べる GPR のカーネル：fitrgp と同じ10種類と、ν を指定する Matérn（等方・ARD）、周期カーネル
%   （等方・ARD。alignest.models.gprSetup）。
%   matern・ardmatern は、設定の methods.gpr.maternNu の値ごとに matern_nu<ν>・ardmatern_nu<ν> に展開する。
fixed = alignest.models.gprKernelNames();
names = [fixed, "matern", "ardmatern", "periodic", "ardperiodic"];
labels = [fixed, "matern（ν を指定）", "ardmatern（ν を指定）", "periodic（周期）", "ardperiodic（周期・ARD）"];
end
