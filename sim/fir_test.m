% fir_test does a very basic check on the FIR module simulation result.
%
% The test bench for module fir.vhdl (fir_tb.vhdl) should be launched with 
% Modelsim script 'fir_tb.do'. 
% The simulation will log its results onto file 'fir_log.m'. This log will 
% include the filter test input, the output and some test parameters. They 
% are logged as a plain .m file for simplicity.
% This script 'fir_test.m' will run script 'fir_log.m' and then perform 
% a very basic check on the computed filter output.
%
% Please note that the current test bench uses a single input signal and a
% single h[n] vector. It is meant as a simple visual demonstration tool 
% and NOT as a real, solid test bench.
%

% Clear the working space and close all graph windows...
clear all;
close all;
% ...then 'run' the simulation log.
fir_log

% The script fir_log will have left some variables in the workspace:
%
% h :   Impulse response in fixed point format.
% hr :  Impulse response in float format (i.e. not quantized).
% x :   Filter input -- vector of fixed point samples.
% y :   Filter output -- vector of fixed point samples, scaled.
%
% Plus a few configuration constants:
%
% sample_width : Bit width of input samples AND filter coefficients.
% sample_integer_part : Number of integer bits in x and h.
% output_truncated_width : Size of truncated filter output.
% 
% All vectors are column vectors unless stated otherwise.

% The output actually computed by the circuit and logged by the test bench 
% will be scaled by two independent factors:

% 1.- The output is divided by the number of coefficients (not necessarily 
% a power of two).
% NOTE: this is so because the output sample is assumed to have 0 integer
% bits, for simplicity.
convolution_scale = 1/length(h);

% 2.- The output is truncated before logging it to a file, strictly for 
% convenience: we want to deal with 32-bit numbers only. 
% The truncation keeps the MSBs, including the duplicate sign bit.
y_truncation_scale = 2^(-(2*sample_width-output_truncated_width));


% Ok, now compute the convolution...
z = conv(h, x);
% ...truncate the vector to the same size as what's in the log...
if length(z) ~= length(y)
    m = min(length(z),length(y));
    z = z(1:m);
end;
% ...scale it with the same factors applied by the actual logic...
z = z * (convolution_scale * y_truncation_scale);
% ...and match it against what's in the log.
error = z - y;
% Our error estimator will be the ratio of absolute summations, again for
% simplicity -- all we want is to catch errors at a glance.
if sum(abs(z)) > 0
    rel_error = sum(abs(error))/sum(abs(z));
    disp(sprintf('Relative error: %f\n', rel_error));
else
    rel_error = 1.0;
    disp('Relative error can''t be computed: null output.');  
end

% Draw expected and actual result for illustration.
figure('Name','FIR module test bench');
subplot(311);
stem(z, 'xb');
hold on;
stem(y, 'r');
grid on;
legend('True convolution','Computed convolution');
title(sprintf('Convolution: expected vs. actual (relative error = %6.3f)', rel_error));
subplot(312);
stem(h);
grid on;
title('h[n]')
subplot(313);
stem(x);
grid on;
title('x[n]');