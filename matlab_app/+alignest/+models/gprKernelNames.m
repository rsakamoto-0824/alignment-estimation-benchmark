function names = gprKernelNames()
%GPRKERNELNAMES MATLAB fitrgp と同じ10種類のカーネル名（KernelFunction の名前と同じ）。
names = ["exponential", "squaredexponential", "matern32", "matern52", "rationalquadratic", ...
    "ardexponential", "ardsquaredexponential", "ardmatern32", "ardmatern52", "ardrationalquadratic"];
end
