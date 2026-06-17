% setup_ball_beam.m
% Place in: experiments/nonlinear/ball_beam/
% Model file: ballBeam.slx (NOT ball.slx)

model = 'ballBeam';

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

% Configure solver
set_param(model, 'SolverType', 'Fixed-step');
set_param(model, 'Solver',     'ode14x');
set_param(model, 'FixedStep',  '0.001');
set_param(model, 'StopTime',   num2str(t_stop));
save_system(model);

fprintf('  Ball beam setup done\n');
