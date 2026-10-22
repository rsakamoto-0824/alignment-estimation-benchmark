function [names, labels] = gamKernelChoices()
%GAMKERNELCHOICES GAM のガウス過程の形状関数で選べるカーネル（等方。alignest.models.stationaryKernel）。
%   matern（ν を指定）は、設定の methods.gam.gpMaternNu の値ごとに matern_nu<ν> に展開する。
%   長さスケールは項ごとに1つ（ARD は使わない）。
names = ["exponential", "squaredexponential", "matern32", "matern52", "rationalquadratic", "matern"];
labels = ["exponential", "squaredexponential", "matern32", "matern52", "rationalquadratic（α = 1）", "matern（ν を指定）"];
end
