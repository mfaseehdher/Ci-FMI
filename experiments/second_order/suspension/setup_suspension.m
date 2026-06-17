% setup_suspension.m
model = 'suspmod';

M1 = 2500;  M2 = 320;
K1 = 80000; K2 = 500000;
b1 = 350;   b2 = 15020;
assignin('base','M1',M1); assignin('base','M2',M2);
assignin('base','K1',K1); assignin('base','K2',K2);
assignin('base','b1',b1); assignin('base','b2',b2);

t_stop = 5;
t = (0:0.001:t_stop)';
u = 0.1 * ones(size(t));
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

t_out  = tout;
out    = yout{1}.Values.Data(:);

fid = fopen('suspmod_ref.csv', 'w');
fprintf(fid, 'time,BodyDisplacement\r\n');
for i = 1:length(t_out)
    fprintf(fid, '%.10f,%.10f\r\n', t_out(i), out(i));
end
fclose(fid);
fprintf('  Suspension workspace ready\n');
fprintf('  Reference saved: suspmod_ref.csv (%d rows)\n', length(t_out));
