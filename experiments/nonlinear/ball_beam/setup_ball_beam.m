% setup_ball_beam.m
% Sets workspace variables for ball.slx

m = 0.111; R = 0.015; g = -9.8;
L = 1.0; d = 0.03; J = 9.99e-6;
assignin('base', 'm', m); assignin('base', 'R', R);
assignin('base', 'g', g); assignin('base', 'L', L);
assignin('base', 'd', d); assignin('base', 'J', J);

t_stop = 5;
t = (0 : 0.001 : t_stop)';
u = 0.1 * ones(size(t));
assignin('base', 't', t);
assignin('base', 'u', u);

load_system('ball');
set_param('ball', 'SolverType',        'Fixed-step');
set_param('ball', 'Solver',            'ode14x');
set_param('ball', 'FixedStep',         '0.001');
set_param('ball', 'StopTime',          num2str(t_stop));
set_param('ball', 'LoadExternalInput', 'on');
set_param('ball', 'ExternalInput',     '[t, u]');
save_system('ball');
fprintf('  Ball beam workspace ready\n');
