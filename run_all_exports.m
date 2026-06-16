function run_all_exports(experiments_dir)
% RUN_ALL_EXPORTS
%
% Finds all .slx files in experiments directory and for each model:
%   1. Loads the Simulink model
%   2. Runs simulation --> saves reference CSV
%   3. Exports FMU
%   4. Generates experiment JSON automatically
%
% The generated files go into the SAME folder as the .slx file.
%
% Usage from GitLab/GitHub pipeline:
%   matlab -batch "run_all_exports('experiments')"
%
% Usage from MATLAB command window:
%   run_all_exports('experiments')
%
% Folder structure expected:
%   experiments/
%     first_order/
%       cruise_control/
%         ccmodel.slx          <-- you commit this
%     second_order/
%       suspension/
%         suspension.slx       <-- you commit this
%
% Files generated automatically per model:
%   ccmodel.fmu                <-- FMU export
%   cruise_control_ref.csv     <-- MATLAB simulation reference
%   cruise_control.json        <-- experiment config for generic.py

if nargin < 1
    experiments_dir = 'experiments';
end

fprintf('================================================\n');
fprintf('  MATLAB Export Pipeline\n');
fprintf('  Looking in: %s\n', experiments_dir);
fprintf('================================================\n\n');

% Find all .slx files recursively
slx_files = dir(fullfile(experiments_dir, '**', '*.slx'));

if isempty(slx_files)
    error('No .slx files found in %s', experiments_dir);
end

fprintf('Found %d model(s)\n\n', numel(slx_files));

passed = {};
failed = {};

for i = 1:numel(slx_files)
    model_dir  = slx_files(i).folder;
    slx_name   = slx_files(i).name;
    model_name = erase(slx_name, '.slx');

    fprintf('--- [%d/%d] %s ---\n', i, numel(slx_files), model_name);

    try
        process_one_model(model_name, model_dir);
        passed{end+1} = model_name;
        fprintf('[%s] SUCCESS\n\n', model_name);
    catch e
        failed{end+1} = model_name;
        fprintf('[%s] FAILED: %s\n\n', model_name, e.message);
    end
end

% Summary
fprintf('================================================\n');
fprintf('  Summary: %d passed, %d failed\n', numel(passed), numel(failed));
for i = 1:numel(passed)
    fprintf('  PASS: %s\n', passed{i});
end
for i = 1:numel(failed)
    fprintf('  FAIL: %s\n', failed{i});
end
fprintf('================================================\n');

if ~isempty(failed)
    error('Some models failed to export.');
end

end


% =============================================================
% Process one Simulink model
% =============================================================
function process_one_model(model_name, model_dir)

original_dir = pwd;
cd(model_dir);

try
    % Step 1: Load model
    fprintf('  [1/4] Loading %s...\n', model_name);
    load_system(model_name);

    stop_time = str2double(get_param(model_name, 'StopTime'));
    dt_str    = get_param(model_name, 'FixedStep');
    if strcmp(dt_str, 'auto')
        dt = 0.01;
    else
        dt = str2double(dt_str);
        if isnan(dt), dt = 0.01; end
    end
    fprintf('     Stop time: %gs  Step size: %gs\n', stop_time, dt);

    % Step 2: Run simulation and save reference CSV
    fprintf('  [2/4] Running simulation...\n');
    simOut   = sim(model_name, 'ReturnWorkspaceOutputs', 'on');
    ref_csv  = sprintf('%s_ref.csv', model_name);
    save_reference_csv(simOut, ref_csv, model_name);
    fprintf('     Reference saved: %s\n', ref_csv);

    % Step 3: Export FMU
    fprintf('  [3/4] Exporting FMU...\n');
    exportToFMU2CS(model_name, ...
        'SaveDirectory',         model_dir, ...
        'SolverForCoSimulation', 'FixedStepAuto');
    fprintf('     FMU exported: %s.fmu\n', model_name);

    % Step 4: Generate experiment JSON
    fprintf('  [4/4] Generating experiment JSON...\n');
    generate_json(model_name, model_dir, stop_time, dt);
    fprintf('     JSON generated: %s.json\n', model_name);

    close_system(model_name, 0);

catch e
    cd(original_dir);
    rethrow(e);
end

cd(original_dir);
end


% =============================================================
% Save simulation output as reference CSV
% =============================================================
function save_reference_csv(simOut, csv_path, model_name)

try
    % Method 1: logged signals (logsout) -- modern Simulink
    if isprop(simOut, 'logsout') && ~isempty(simOut.logsout)
        logs         = simOut.logsout;
        signal_names = logs.getElementNames();

        if isempty(signal_names)
            warning('[%s] logsout is empty. Enable signal logging.', model_name);
        else
            first = logs.getElement(signal_names{1});
            time  = first.Values.Time;

            fid = fopen(csv_path, 'w');
            % Header
            fprintf(fid, 'time');
            for i = 1:numel(signal_names)
                fprintf(fid, ',%s', signal_names{i});
            end
            fprintf(fid, '\r\n');
            % Data rows
            for row = 1:length(time)
                fprintf(fid, '%.10f', time(row));
                for i = 1:numel(signal_names)
                    sig = logs.getElement(signal_names{i});
                    val = sig.Values.Data(row);
                    fprintf(fid, ',%.10f', val);
                end
                fprintf(fid, '\r\n');
            end
            fclose(fid);
            fprintf('     Saved %d signal(s), %d rows\n', ...
                numel(signal_names), length(time));
            return
        end
    end

    % Method 2: tout/yout -- older Simulink
    if isprop(simOut, 'tout') && ~isempty(simOut.tout)
        time = simOut.tout;
        yout = simOut.yout;
        fid  = fopen(csv_path, 'w');
        fprintf(fid, 'time');
        for i = 1:size(yout, 2)
            fprintf(fid, ',y%d', i);
        end
        fprintf(fid, '\r\n');
        for row = 1:length(time)
            fprintf(fid, '%.10f', time(row));
            for col = 1:size(yout, 2)
                fprintf(fid, ',%.10f', yout(row, col));
            end
            fprintf(fid, '\r\n');
        end
        fclose(fid);
        fprintf('     Saved yout with %d column(s)\n', size(yout, 2));
        return
    end

    error('No logged signals found. Enable signal logging in Simulink.');

catch e
    rethrow(e);
end

end


% =============================================================
% Generate experiment JSON for generic.py
% =============================================================
function generate_json(model_name, model_dir, stop_time, dt)

% Find signal generator blocks inside the model
step_blocks  = find_system(model_name, 'BlockType', 'Step');
sine_blocks  = find_system(model_name, 'BlockType', 'SineWave');
ramp_blocks  = find_system(model_name, 'BlockType', 'Ramp');
out_blocks   = find_system(model_name, 'BlockType', 'Outport');

components  = struct();
connections = {};

% Step signal blocks
if ~isempty(step_blocks)
    ports = struct();
    for i = 1:numel(step_blocks)
        pname = clean_name(get_param(step_blocks{i}, 'Name'));
        ports.(pname) = struct( ...
            'initial',   str2double(get_param(step_blocks{i}, 'Before')), ...
            'step',      str2double(get_param(step_blocks{i}, 'After')), ...
            'step_time', str2double(get_param(step_blocks{i}, 'Time')));
        connections{end+1} = conn('step_source', pname, 'fmu', pname);
    end
    components.step_source = struct('type', 'step', 'ports', ports);
end

% Sine signal blocks
if ~isempty(sine_blocks)
    ports = struct();
    for i = 1:numel(sine_blocks)
        pname    = clean_name(get_param(sine_blocks{i}, 'Name'));
        freq_rad = str2double(get_param(sine_blocks{i}, 'Frequency'));
        ports.(pname) = struct( ...
            'amplitude', str2double(get_param(sine_blocks{i}, 'Amplitude')), ...
            'frequency', freq_rad / (2*pi), ...
            'phase',     str2double(get_param(sine_blocks{i}, 'Phase')), ...
            'bias',      str2double(get_param(sine_blocks{i}, 'Bias')));
        connections{end+1} = conn('sine_source', pname, 'fmu', pname);
    end
    components.sine_source = struct('type', 'sine', 'ports', ports);
end

% Ramp signal blocks
if ~isempty(ramp_blocks)
    ports = struct();
    for i = 1:numel(ramp_blocks)
        pname = clean_name(get_param(ramp_blocks{i}, 'Name'));
        ports.(pname) = struct( ...
            'initial',    str2double(get_param(ramp_blocks{i}, 'X0')), ...
            'slope',      str2double(get_param(ramp_blocks{i}, 'slope')), ...
            'start_time', str2double(get_param(ramp_blocks{i}, 'start')));
        connections{end+1} = conn('ramp_source', pname, 'fmu', pname);
    end
    components.ramp_source = struct('type', 'ramp', 'ports', ports);
end

% FMU component
fmu_files = dir(fullfile(model_dir, '*.fmu'));
if ~isempty(fmu_files)
    fmu_file = fmu_files(1).name;
else
    fmu_file = sprintf('%s.fmu', model_name);
end
components.fmu = struct('type', 'fmu', 'file', fmu_file);

% Logger component
results_file        = sprintf('results_%s.csv', model_name);
components.log      = struct('type', 'logger', 'file', results_file);

% Wire FMU outputs to logger
for i = 1:numel(out_blocks)
    pname = clean_name(get_param(out_blocks{i}, 'Name'));
    connections{end+1} = conn('fmu', pname, 'log', pname);
end

% Build and write JSON
experiment = struct();
experiment.start       = 0.0;
experiment.stop        = stop_time;
experiment.dt          = dt;
experiment.components  = components;
experiment.connections = connections;

json_str  = jsonencode(experiment, 'PrettyPrint', true);
json_path = fullfile(model_dir, sprintf('%s.json', model_name));
fid = fopen(json_path, 'w');
fprintf(fid, '%s', json_str);
fclose(fid);

end


% =============================================================
% Helpers
% =============================================================
function c = conn(src_comp, src_port, dst_comp, dst_port)
c = struct('src_comp', src_comp, 'src_port', src_port, ...
           'dst_comp', dst_comp, 'dst_port', dst_port);
end

function name = clean_name(raw)
name = regexprep(raw, '[^A-Za-z0-9_]', '_');
if ~isempty(name) && isstrprop(name(1), 'digit')
    name = ['_' name];
end
end
