% setup_aircraft_pitch.m
model = 'aircraft_pitch_control';

A = [-0.313  56.7   0; -0.0139 -0.426 0; 0 56.7 0];
B = [0.232; 0.0203; 0];
C = [0 0 1];
D = [0];
K = [-0.6435 169.6950 7.0711];
assignin('base', 'A', A); assignin('base', 'B', B);
assignin('base', 'C', C); assignin('base', 'D', D);
assignin('base', 'K', K);

t_stop = 10;
t = (0 : 0.001 : t_stop)';
u = 0.2 * ones(size(t));
assignin('base', 't', t);
assignin('base', 'u', u);

set_param(model, 'SolverType', 'Fixed-step');
set_param(model, 'Solver',     'ode4');
set_param(model, 'FixedStep',  '0.001');
set_param(model, 'StopTime',   num2str(t_stop));
save_system(model);

fprintf('  Aircraft pitch setup done\n');
