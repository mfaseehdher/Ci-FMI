function run_all_exports(experiments_dir)
% RUN_ALL_EXPORTS
% Finds all .slx files in experiments directory and for each model:
%   1. Runs the model's own setup .m file if it exists
%   2. Runs simulation --> saves reference CSV
%   3. Exports FMU
%   4. Generates experiment JSON
%
% Usage from pipeline:
%   matlab -batch "run_all_exports('experiments')"

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
function process_one_model(model_name, model_dir)

original_dir = pwd;
cd(model_dir);

try
    % Step 1: Run setup .m file if it exists
    % This loads workspace variables needed by the model
    setup_files = dir('*.m');
    for i = 1:numel(setup_files)
        setup_name = erase(setup_files(i).name, '.m');
        fprintf('  [0/4] Running setup script: %s\n', setup_files(i).name);
        try
            run(setup_name);
            fprintf('     Setup complete\n');
        catch e
            fprintf('     Setup warning: %s\n', e.message);
        end
    end

    % Step 2: Load model
    fprintf('  [1/4] Loading %s...\n', model_name);
    load_system(model_name);

    stop_time = str2double(get_param(model_name, 'StopTime'));
    dt_str    = get_param(model_name, 'FixedStep');
    if strcmp(dt_str, 'auto') || isnan(str2double(dt_str))
        dt = 0.01;
    else
        dt = str2double(dt_str);
    end
    fprintf('     Stop time: %gs  Step size: %gs\n', stop_time, dt);

    % Step 3: Run simulation and save reference CSV
    fprintf('  [2/4] Running simulation...\n');
    simOut  = sim(model_name, 'ReturnWorkspaceOutputs', 'on');
    ref_csv = sprintf('%s_ref.csv', model_name);
    save_reference_csv(simOut, ref_csv, model_name);
    fprintf('     Reference saved: %s\n', ref_csv);

    % Step 4: Export FMU
    fprintf('  [3/4] Exporting FMU...\n');
    exportToFMU2CS(model_name, ...
        'SaveDirectory',         model_dir, ...
        'SolverForCoSimulation', 'FixedStepAuto');
    fprintf('     FMU exported: %s.fmu\n', model_name);

    % Step 5: Generate experiment JSON
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
function save_reference_csv(simOut, csv_path, model_name)

% Method 1: logsout (modern Simulink - logged signals)
try
    if isprop(simOut, 'logsout') && ~isempty(simOut.logsout)
        logs         = simOut.logsout;
        signal_names = logs.getElementNames();
        if ~isempty(signal_names)
            first = logs.getElement(signal_names{1});
            time  = first.Values.Time;
            fid   = fopen(csv_path, 'w');
            fprintf(fid, 'time');
            for i = 1:numel(signal_names)
                fprintf(fid, ',%s', signal_names{i});
            end
            fprintf(fid, '\r\n');
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
            fprintf('     Saved %d logged signal(s), %d rows\n', ...
                numel(signal_names), length(time));
            return
        end
    end
catch
end

% Method 2: get variables from base workspace (set by setup .m file)
% This handles models where output is saved to workspace by the .m file
try
    t_vars = {'t', 'tout', 'time', 'T'};
    y_vars = {'y', 'yout', 'out', 'velocity', 'Velocity', ...
              'omega', 'theta', 'position', 'pitch', 'ball_pos'};

    time_data = [];
    for i = 1:numel(t_vars)
        if evalin('base', sprintf('exist(''%s'', ''var'')', t_vars{i}))
            time_data = evalin('base', t_vars{i});
            break
        end
    end

    % Also check simOut properties
    if isempty(time_data) && isprop(simOut, 'tout')
        time_data = simOut.tout;
    end

    if isempty(time_data)
        error('No time data found');
    end

    % Find output data
    out_data  = [];
    out_name  = 'y';
    for i = 1:numel(y_vars)
        if evalin('base', sprintf('exist(''%s'', ''var'')', y_vars{i}))
            out_data = evalin('base', y_vars{i});
            out_name = y_vars{i};
            break
        end
    end

    if isempty(out_data) && isprop(simOut, 'yout')
        out_data = simOut.yout;
        out_name = 'y';
    end

    if isempty(out_data)
        error('No output data found in workspace or simOut');
    end

    % Make sure sizes match
    min_len  = min(length(time_data), size(out_data, 1));
    time_data = time_data(1:min_len);
    out_data  = out_data(1:min_len, :);

    fid = fopen(csv_path, 'w');
    if size(out_data, 2) == 1
        fprintf(fid, 'time,%s\r\n', out_name);
        for row = 1:min_len
            fprintf(fid, '%.10f,%.10f\r\n', time_data(row), out_data(row));
        end
    else
        fprintf(fid, 'time');
        for col = 1:size(out_data, 2)
            fprintf(fid, ',%s%d', out_name, col);
        end
        fprintf(fid, '\r\n');
        for row = 1:min_len
            fprintf(fid, '%.10f', time_data(row));
            for col = 1:size(out_data, 2)
                fprintf(fid, ',%.10f', out_data(row, col));
            end
            fprintf(fid, '\r\n');
        end
    end
    fclose(fid);
    fprintf('     Saved from workspace variable "%s", %d rows\n', ...
        out_name, min_len);
    return

catch e
    fprintf('     WARNING: %s\n', e.message);
end

error(['Could not save reference CSV for %s.\n' ...
       'Make sure either:\n' ...
       '  1. Signal logging is enabled in Simulink (right-click signal -> Log)\n' ...
       '  OR\n' ...
       '  2. Your setup .m file saves output to workspace variables'], model_name);
end


% =============================================================
function generate_json(model_name, model_dir, stop_time, dt)

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
        try
            initial   = str2double(get_param(step_blocks{i}, 'Before'));
            step_val  = str2double(get_param(step_blocks{i}, 'After'));
            step_time = str2double(get_param(step_blocks{i}, 'Time'));
            if isnan(initial),   initial   = 0; end
            if isnan(step_val),  step_val  = 1; end
            if isnan(step_time), step_time = 0; end
        catch
            initial = 0; step_val = 1; step_time = 0;
        end
        ports.(pname) = struct('initial', initial, ...
                               'step', step_val, ...
                               'step_time', step_time);
        connections{end+1} = conn('step_source', pname, 'fmu', pname);
    end
    components.step_source = struct('type', 'step', 'ports', ports);
end

% Sine signal blocks
if ~isempty(sine_blocks)
    ports = struct();
    for i = 1:numel(sine_blocks)
        pname = clean_name(get_param(sine_blocks{i}, 'Name'));
        try
            amp      = str2double(get_param(sine_blocks{i}, 'Amplitude'));
            freq_rad = str2double(get_param(sine_blocks{i}, 'Frequency'));
            phase    = str2double(get_param(sine_blocks{i}, 'Phase'));
            bias     = str2double(get_param(sine_blocks{i}, 'Bias'));
            if isnan(amp),  amp  = 1; end
            if isnan(freq_rad), freq_rad = 1; end
            if isnan(phase), phase = 0; end
            if isnan(bias),  bias  = 0; end
        catch
            amp = 1; freq_rad = 1; phase = 0; bias = 0;
        end
        ports.(pname) = struct('amplitude', amp, ...
                               'frequency', freq_rad/(2*pi), ...
                               'phase', phase, 'bias', bias);
        connections{end+1} = conn('sine_source', pname, 'fmu', pname);
    end
    components.sine_source = struct('type', 'sine', 'ports', ports);
end

% FMU component
fmu_files = dir(fullfile(model_dir, '*.fmu'));
if ~isempty(fmu_files)
    fmu_file = fmu_files(1).name;
else
    fmu_file = sprintf('%s.fmu', model_name);
end
components.fmu = struct('type', 'fmu', 'file', fmu_file);

% Logger
results_file   = sprintf('results_%s.csv', model_name);
components.log = struct('type', 'logger', 'file', results_file);

% Wire FMU outputs to logger
for i = 1:numel(out_blocks)
    pname = clean_name(get_param(out_blocks{i}, 'Name'));
    connections{end+1} = conn('fmu', pname, 'log', pname);
end

% Write JSON
experiment             = struct();
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
