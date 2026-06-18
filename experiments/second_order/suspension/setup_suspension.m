% setup_suspension.m
% suspmod = CTMS Suspension (old Simulink 2.0 format)
% Uses LOWERCASE variable names: m1 m2 k1 k2 b1 b2
% No scope - has Outport, so yout works

model = 'suspmod';

% Lowercase variable names (as the model expects)
m1 = 2500;   m2 = 320;
k1 = 80000;  k2 = 500000;
b1 = 350;    b2 = 15020;
assignin('base','m1',m1); assignin('base','m2',m2);
assignin('base','k1',k1); assignin('base','k2',k2);
assignin('base','b1',b1); assignin('base','b2',b2);

u = 0.1;
assignin('base','u',u);

t_stop = 5;

load_system(model);
set_param(model,'SolverType','Fixed-step');
set_param(model,'Solver','ode4');
set_param(model,'FixedStep','0.01');
set_param(model,'StopTime',num2str(t_stop));
set_param(model,'SaveState','off');
set_param(model,'SignalLogging','on');
set_param(model,'SignalLoggingName','logsout');

% Enable logging on scope input lines (if any)
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
out     = [];

% Try yout first (suspension has Outport)
if ismember('yout', who_vars)
    raw = simOut.yout;
    if isa(raw, 'Simulink.SimulationData.Dataset')
        out = raw{1}.Values.Data(:);
        fprintf('  Got data from yout Dataset\n');
    elseif isnumeric(raw)
        out = raw(:,1);
        fprintf('  Got data from yout array\n');
    end
end

% Try logsout as backup
if isempty(out) && ismember('logsout', who_vars)
    logs = simOut.logsout;
    try
        if logs.numElements > 0
            elem  = logs.getElement(1);
            out   = elem.Values.Data(:);
            t_out = elem.Values.Time(:);
            fprintf('  Got data from logsout\n');
        end
    catch
    end
end

if isempty(out)
    error('No output captured for suspension.');
end

fid = fopen('suspmod_ref.csv', 'w');
fprintf(fid, 'time,BodyDisplacement\r\n');
for i = 1:min(length(t_out),length(out))
    fprintf(fid, '%.10f,%.10f\r\n', t_out(i), out(i));
end
fclose(fid);
fprintf('  DONE: %d rows saved\n', min(length(t_out),length(out)));
