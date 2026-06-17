% setup_motor_position.m
% Sets workspace variables for Motor_Pos.slx

K = 0.01; J = 0.01; b = 0.1; R = 1.0; L = 0.5;
assignin('base', 'K', K);
assignin('base', 'J', J);
assignin('base', 'b', b);
assignin('base', 'R', R);
assignin('base', 'L', L);

t_stop = 10;
t = (0 : 0.001 : t_stop)';
u = 1.0 * ones(size(t));
assignin('base', 't', t);
assignin('base', 'u', u);

load_system('Motor_Pos');
set_param('Motor_Pos', 'SolverType',        'Fixed-step');
set_param('Motor_Pos', 'Solver',            'ode14x');
set_param('Motor_Pos', 'FixedStep',         '0.001');
set_param('Motor_Pos', 'StopTime',          num2str(t_stop));
set_param('Motor_Pos', 'LoadExternalInput', 'on');
set_param('Motor_Pos', 'ExternalInput',     '[t, u]');
save_system('Motor_Pos');
fprintf('  Motor position workspace ready\n');
