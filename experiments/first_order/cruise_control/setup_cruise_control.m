% setup_cruise_control.m
% Sets workspace variables for ccmodel.slx
% Called automatically by run_all_exports.m before simulation

m = 1000;  b = 50;
assignin('base', 'm', m);
assignin('base', 'b', b);

t_stop = 120;  dt_sim = 0.001;
t = (0 : dt_sim : t_stop)';
u = 500 * ones(size(t));
assignin('base', 't', t);
assignin('base', 'u', u);

% Configure solver
load_system('ccmodel');
set_param('ccmodel', 'SolverType', 'Fixed-step');
set_param('ccmodel', 'Solver',     'ode4');
set_param('ccmodel', 'FixedStep',  '0.001');
set_param('ccmodel', 'StopTime',   num2str(t_stop));
set_param('ccmodel', 'LoadExternalInput', 'on');
set_param('ccmodel', 'ExternalInput',     '[t, u]');
save_system('ccmodel');
fprintf('  Cruise control workspace ready\n');
