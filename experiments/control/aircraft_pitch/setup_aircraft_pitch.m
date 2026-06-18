% setup_aircraft_pitch.m
% aircraft_pitch_control = CTMS Aircraft Pitch (output to Scope)
% Uses scope-logging pattern

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

% Step input value (desired pitch)
u = 0.2;
assignin('base','u',u);

t_stop = 10;

load_system(model);
set_param(model,'SolverType','Fixed-step');
set_param(model,'Solver','ode4');
set_param(model,'FixedStep','0.01');
set_param(model,'StopTime',num2str(t_stop));
set_param(model,'SaveState','off');
set_param(model,'SignalLogging','on');
set_param(model,'SignalLoggingName','logsout');

% Enable logging on scope input lines
scopes = find_system(model, 'BlockType', 'Scope');
fprintf('Found %d scope(s)\n', numel(scopes));
for s = 1:numel(scopes)
    ph = get_param(scopes{s}, 'PortHandles');
    if ~isempty(ph.Inport)
        lh = get_param(ph.Inport(1), 'Line');
        if lh ~= -1
            try
                set(lh, 'DataLogging', 1);
                fprintf('  Logging enabled on scope %d\n', s);
            catch
                try
                    set_param(lh, 'DataLogging', 'on');
                catch
                end
            end
        end
    end
end

save_system(model);

simOut = sim(model, 'ReturnWorkspaceOutputs', 'on');

who_vars = simOut.who;
t_out   = simOut.tout(:);
out     = [];

if ismember('logsout', who_vars)
    logs = simOut.logsout;
    try
        if logs.numElements > 0
            elem  = logs.getElement(1);
            out   = elem.Values.Data(:);
            t_out = elem.Values.Time(:);
            fprintf('  Got data from logsout (%d points)\n', length(out));
        end
    catch
    end
end

if isempty(out) && ismember('yout', who_vars)
    raw = simOut.yout;
    if isa(raw, 'Simulink.SimulationData.Dataset')
        out = raw{1}.Values.Data(:);
    elseif isnumeric(raw)
        out = raw(:,1);
    end
end

if isempty(out)
    error('No output captured for aircraft_pitch.');
end

fid = fopen('aircraft_pitch_control_ref.csv', 'w');
fprintf(fid, 'time,PitchAngle\r\n');
for i = 1:min(length(t_out),length(out))
    fprintf(fid, '%.10f,%.10f\r\n', t_out(i), out(i));
end
fclose(fid);
fprintf('  DONE: %d rows saved\n', min(length(t_out),length(out)));
