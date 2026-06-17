% setup_suspension.m
% Sets workspace variables for suspmod.slx

M1 = 2500; M2 = 320;
K1 = 80000; K2 = 500000;
b1 = 350; b2 = 15020;
assignin('base', 'M1', M1); assignin('base', 'M2', M2);
assignin('base', 'K1', K1); assignin('base', 'K2', K2);
assignin('base', 'b1', b1); assignin('base', 'b2', b2);

t_stop = 5;
t = (0 : 0.001 : t_stop)';
u = 0.1 * ones(size(t));
assignin('base', 't', t);
assignin('base', 'u', u);

load_system('suspmod');
set_param('suspmod', 'SolverType',        'Fixed-step');
set_param('suspmod', 'Solver',            'ode4');
set_param('suspmod', 'FixedStep',         '0.001');
set_param('suspmod', 'StopTime',          num2str(t_stop));
set_param('suspmod', 'LoadExternalInput', 'on');
set_param('suspmod', 'ExternalInput',     '[t, u]');
save_system('suspmod');
fprintf('  Suspension workspace ready\n');
