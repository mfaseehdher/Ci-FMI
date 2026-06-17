% setup_cruise_control.m
% Exact copy of cruise_control_export_and_reference.m
% MINUS the FMU export (run_all_exports.m handles that)

model = 'ccmodel';

m = 1000;  b = 50;
assignin('base', 'm', m);
assignin('base', 'b', b);

t_stop = 120;  dt_sim = 0.001;
t = (0 : dt_sim : t_stop)';
u = 500 * ones(size(t));
assignin('base', 't', t);
assignin('base', 'u', u);

load_system(model);
set_param(model, 'SolverType', 'Fixed-step');
set_param(model, 'Solver',     'ode4');
set_param(model, 'FixedStep',  '0.001');
set_param(model, 'StopTime',   num2str(t_stop));
save_system(model);

sim(model);

t_out   = tout;
vel_out = yout{1}.Values.Data(:);

fid = fopen('ccmodel_ref.csv', 'w');
fprintf(fid, 'time,Velocity\r\n');
for i = 1:length(t_out)
    fprintf(fid, '%.10f,%.10f\r\n', t_out(i), vel_out(i));
end
fclose(fid);
fprintf('  Cruise control workspace ready\n');
fprintf('  Reference saved: ccmodel_ref.csv (%d rows)\n', length(t_out));
