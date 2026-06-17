% setup_aircraft_pitch.m
% NOTE: model file is aircraft_pitch_control.slx
% Old script used 'pitch_control' - now using correct name
model = 'aircraft_pitch_control';

A = [-0.313  56.7   0;
     -0.0139 -0.426 0;
      0       56.7  0];
B = [0.232; 0.0203; 0];
C = [0 0 1];
D = [0];
K = [-0.6435 169.6950 7.0711];
assignin('base','A',A); assignin('base','B',B);
assignin('base','C',C); assignin('base','D',D);
assignin('base','K',K);

t_stop = 10;
t = (0:0.001:t_stop)';
u = 0.2 * ones(size(t));
assignin('base','t',t);
assignin('base','u',u);

load_system(model);
set_param(model,'SolverType','Fixed-step');
set_param(model,'Solver','ode4');
set_param(model,'FixedStep','0.001');
set_param(model,'StopTime',num2str(t_stop));
set_param(model,'LoadExternalInput','on');
set_param(model,'ExternalInput','[t, u]');
save_system(model);

sim(model);

t_out = tout;
out   = yout{1}.Values.Data(:);

fid = fopen('aircraft_pitch_control_ref.csv', 'w');
fprintf(fid, 'time,PitchAngle\r\n');
for i = 1:length(t_out)
    fprintf(fid, '%.10f,%.10f\r\n', t_out(i), out(i));
end
fclose(fid);
fprintf('  Aircraft pitch workspace ready\n');
fprintf('  Reference saved: aircraft_pitch_control_ref.csv (%d rows)\n', length(t_out));
