% setup_motor_speed.m
% Sets workspace variables for Motor_Model.slx

K = 0.01; J = 0.01; b = 0.1; R = 1.0; L = 0.5;
assignin('base', 'K', K);
assignin('base', 'J', J);
assignin('base', 'b', b);
assignin('base', 'R', R);
assignin('base', 'L', L);

t_stop = 3;
t = (0 : 0.001 : t_stop)';
u = 1.0 * ones(size(t));
assignin('base', 't', t);
assignin('base', 'u', u);

load_system('Motor_Model');
set_param('Motor_Model', 'SolverType',        'Fixed-step');
set_param('Motor_Model', 'Solver',            'ode14x');
set_param('Motor_Model', 'FixedStep',         '0.001');
set_param('Motor_Model', 'StopTime',          num2str(t_stop));
set_param('Motor_Model', 'LoadExternalInput', 'on');
set_param('Motor_Model', 'ExternalInput',     '[t, u]');
save_system('Motor_Model');
fprintf('  Motor speed workspace ready\n');
