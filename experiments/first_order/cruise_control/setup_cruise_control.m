% setup_cruise_control.m
% ccmodel = CTMS cruise control PID model (output to Scope)
% Logs the scope input signal to capture data

model = 'ccmodel';

m = 1000;  b = 50;
assignin('base', 'm', m);
assignin('base', 'b', b);

Kp = 800;  Ki = 40;
assignin('base', 'Kp', Kp);
assignin('base', 'Ki', Ki);

u = 10;
assignin('base', 'u', u);

t_stop = 120;

load_system(model);
set_param(model, 'SolverType', 'Fixed-step');
set_param(model, 'Solver',     'ode4');
set_param(model, 'FixedStep',  '0.01');
set_param(model, 'StopTime',   num2str(t_stop));
set_param(model, 'SaveState',  'off');
set_param(model, 'SignalLogging', 'on');
set_param(model, 'SignalLoggingName', 'logsout');

% Enable logging on scope input lines
scopes = find_system(model, 'BlockType', 'Scope');
fprintf('Found %d scope(s)\n', numel(scopes));

logged_any = false;
for s = 1:numel(scopes)
    ph = get_param(scopes{s}, 'PortHandles');
    if ~isempty(ph.Inport)
        lh = get_param(ph.Inport(1), 'Line');
        if lh ~= -1
            % Newer MATLAB uses these line properties
            try
                set(lh, 'DataLoggingName', sprintf('scope_sig_%d', s));
                set(lh, 'DataLogging', 1);
                logged_any = true;
                fprintf('  Logging enabled on scope %d (method 1)\n', s);
            catch
                try
                    set_param(lh, 'DataLogging', 'on');
                    logged_any = true;
                    fprintf('  Logging enabled on scope %d (method 2)\n', s);
                catch e2
                    fprintf('  Could not log scope %d: %s\n', s, e2.message);
                end
            end
        end
    end
end

save_system(model);

simOut = sim(model, 'ReturnWorkspaceOutputs', 'on');

who_vars = simOut.who;
fprintf('=== simOut contents ===\n');
for i = 1:numel(who_vars)
    fprintf('  Available: %s\n', who_vars{i});
end

t_out   = simOut.tout(:);
vel_out = [];

if ismember('logsout', who_vars)
    logs = simOut.logsout;
    try
        if logs.numElements > 0
            elem    = logs.getElement(1);
            vel_out = elem.Values.Data(:);
            t_out   = elem.Values.Time(:);
            fprintf('  Got data from logsout (%d points)\n', length(vel_out));
        end
    catch
    end
end

if isempty(vel_out) && ismember('yout', who_vars)
    raw = simOut.yout;
    if isa(raw, 'Simulink.SimulationData.Dataset')
        vel_out = raw{1}.Values.Data(:);
    elseif isnumeric(raw)
        vel_out = raw(:,1);
    end
end

if isempty(vel_out)
    error('No output captured. Model may need an Outport added manually.');
end

fid = fopen('ccmodel_ref.csv', 'w');
fprintf(fid, 'time,Velocity\r\n');
for i = 1:min(length(t_out),length(vel_out))
    fprintf(fid, '%.10f,%.10f\r\n', t_out(i), vel_out(i));
end
fclose(fid);
fprintf('  DONE: %d rows saved\n', min(length(t_out),length(vel_out)));
