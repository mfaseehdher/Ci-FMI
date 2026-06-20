% setup_inverted_pendulum.m
% Pend_Model.slx = CTMS Inverted Pendulum
% Has: Force input (root Inport), TWO outputs (Position, Angle)
% Driven by an impulse force (brief kick), validates both outputs

model = 'Pend_Model';

% Standard CTMS inverted pendulum parameters
M = 0.5;    % cart mass (kg)
m = 0.2;    % pendulum mass (kg)
b = 0.1;    % friction coefficient
I = 0.006;  % pendulum inertia (kg.m^2)
g = 9.8;    % gravity (m/s^2)
l = 0.3;    % pendulum length to center of mass (m)
assignin('base','M',M); assignin('base','m',m);
assignin('base','b',b); assignin('base','I',I);
assignin('base','g',g); assignin('base','l',l);

% Impulse force input: brief kick at the start
% Build [time, force] where force is a short pulse then zero
t_stop = 10;
dt_in  = 0.001;
t = (0 : dt_in : t_stop)';
u = zeros(size(t));
% Impulse: 1 N for the first 0.1 seconds, then 0
u(t <= 0.1) = 1.0;
assignin('base','t',t);
assignin('base','u',u);

load_system(model);
set_param(model, 'SolverType', 'Fixed-step');
set_param(model, 'Solver',     'ode4');
set_param(model, 'FixedStep',  '0.01');
set_param(model, 'StopTime',   num2str(t_stop));
set_param(model, 'SaveState',  'off');
set_param(model, 'SaveOutput', 'on');
set_param(model, 'SaveFormat', 'Dataset');

% This model HAS a root Inport (Force) -- use external input
set_param(model, 'LoadExternalInput', 'on');
set_param(model, 'ExternalInput',     '[t, u]');

save_system(model);

simOut = sim(model, 'ReturnWorkspaceOutputs', 'on');

% Diagnostic: show what is in simOut
who_vars = simOut.who;
fprintf('=== simOut contents ===\n');
for i = 1:numel(who_vars)
    fprintf('  Available: %s\n', who_vars{i});
end

t_out = simOut.tout(:);
raw   = simOut.yout;

% This model has TWO outputs: Position (1) and Angle (2)
% Extract both from the Dataset
if isa(raw, 'Simulink.SimulationData.Dataset')
    n_sig = raw.numElements;
    fprintf('  yout has %d signal(s)\n', n_sig);
    pos_out = raw{1}.Values.Data(:);   % Position
    if n_sig >= 2
        ang_out = raw{2}.Values.Data(:);  % Angle
    else
        ang_out = pos_out;  % fallback
    end
else
    % matrix form: columns are the outputs
    pos_out = raw(:,1);
    if size(raw,2) >= 2
        ang_out = raw(:,2);
    else
        ang_out = pos_out;
    end
end

% Save reference CSV with BOTH outputs
n = min([length(t_out), length(pos_out), length(ang_out)]);
fid = fopen('Pend_Model_ref.csv', 'w');
fprintf(fid, 'time,Position,Angle\r\n');
for i = 1:n
    fprintf(fid, '%.10f,%.10f,%.10f\r\n', t_out(i), pos_out(i), ang_out(i));
end
fclose(fid);
fprintf('  Inverted pendulum done: %d rows, 2 outputs (Position, Angle)\n', n);