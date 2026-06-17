% setup_cruise_control.m
% Place in: experiments/first_order/cruise_control/
% Model file: ccmodel.slx

model = 'ccmodel';

m = 1000; b = 50;
assignin('base', 'm', m);
assignin('base', 'b', b);

t_stop = 120; dt_sim = 0.001;
t = (0 : dt_sim : t_stop)';
u = 500 * ones(size(t));
assignin('base', 't', t);
assignin('base', 'u', u);

set_param(model, 'SolverType',        'Fixed-step');
set_param(model, 'Solver',            'ode4');
set_param(model, 'FixedStep',         '0.001');
set_param(model, 'StopTime',          num2str(t_stop));
set_param(model, 'LoadExternalInput', 'on');
set_param(model, 'ExternalInput',     '[t, u]');
save_system(model);
fprintf('  Cruise control workspace ready\n');
