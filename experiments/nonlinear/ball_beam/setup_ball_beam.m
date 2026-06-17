% setup_ball_beam.m
% NOTE: model file is ballBeam.slx but old script used 'ball'
% Using ballBeam as that is the actual file name
model = 'ballBeam';

m = 0.111;  R = 0.015;  g = -9.8;
L = 1.0;    d = 0.03;   J = 9.99e-6;
assignin('base','m',m); assignin('base','R',R);
assignin('base','g',g); assignin('base','L',L);
assignin('base','d',d); assignin('base','J',J);

t_stop = 5;
t = (0:0.001:t_stop)';
u = 0.1 * ones(size(t));
assignin('base','t',t);
assignin('base','u',u);

load_system(model);
set_param(model,'SolverType','Fixed-step');
set_param(model,'Solver','ode14x');
set_param(model,'FixedStep','0.001');
set_param(model,'StopTime',num2str(t_stop));
set_param(model,'LoadExternalInput','on');
set_param(model,'ExternalInput','[t, u]');
save_system(model);

sim(model);

t_out = tout;
out   = yout{1}.Values.Data(:);

fid = fopen('ballBeam_ref.csv', 'w');
fprintf(fid, 'time,BallPosition\r\n');
for i = 1:length(t_out)
    fprintf(fid, '%.10f,%.10f\r\n', t_out(i), out(i));
end
fclose(fid);
fprintf('  Ball beam workspace ready\n');
fprintf('  Reference saved: ballBeam_ref.csv (%d rows)\n', length(t_out));
