% setup_cruise_control.m
% Place in: experiments/first_order/cruise_control/
% NOTE: ccmodel has NO root input port - input is internal

model = 'ccmodel';

m = 1000; b = 50;
assignin('base', 'm', m);
assignin('base', 'b', b);

t_stop = 120;
t = (0 : 0.001 : t_stop)';
u = 500 * ones(size(t));
assignin('base', 't', t);
assignin('base', 'u', u);

% Configure solver - NO LoadExternalInput (model has internal input)
set_param(model, 'SolverType', 'Fixed-step');
set_param(model, 'Solver',     'ode4');
set_param(model, 'FixedStep',  '0.001');
set_param(model, 'StopTime',   num2str(t_stop));
save_system(model);

fprintf('  Cruise control setup done\n');
