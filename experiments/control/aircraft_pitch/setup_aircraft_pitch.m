% setup_aircraft_pitch.m
% Sets workspace variables for pitch_control.slx

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

load_system('pitch_control');
set_param('pitch_control', 'SolverType',        'Fixed-step');
set_param('pitch_control', 'Solver',            'ode4');
set_param('pitch_control', 'FixedStep',         '0.001');
set_param('pitch_control', 'StopTime',          num2str(t_stop));
set_param('pitch_control', 'LoadExternalInput', 'on');
set_param('pitch_control', 'ExternalInput',     '[t, u]');
save_system('pitch_control');
fprintf('  Aircraft pitch workspace ready\n');
