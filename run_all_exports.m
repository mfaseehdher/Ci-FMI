function run_all_exports(experiments_dir)
% RUN_ALL_EXPORTS
% Finds all .slx files in experiments directory and for each model:
%   1. Runs setup .m file to set workspace variables
%   2. Runs simulation -> saves reference CSV
%   3. Exports FMU
%   4. Generates experiment JSON
%
% Usage: matlab -batch "run_all_exports('experiments')"

if nargin < 1
    experiments_dir = 'experiments';
end

fprintf('================================================\n');
fprintf('  MATLAB Export Pipeline\n');
fprintf('  Looking in: %s\n', experiments_dir);
fprintf('================================================\n\n');

slx_files = dir(fullfile(experiments_dir, '**', '*.slx'));
if isempty(slx_files)
    error('No .slx files found in %s', experiments_dir);
end
fprintf('Found %d model(s)\n\n', numel(slx_files));

passed = {}; failed = {};

for i = 1:numel(slx_files)
    model_dir  = slx_files(i).folder;
    model_name = erase(slx_files(i).name, '.slx');
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
for i = 1:numel(passed), fprintf('  PASS: %s\n', passed{i}); end
for i = 1:numel(failed), fprintf('  FAIL: %s\n', failed{i}); end
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
    % Step 0: Load model first so setup scripts can configure it
    fprintf('  [0/4] Pre-loading model...\n');
    load_system(model_name);

    % Step 1: Run setup .m file if it exists
    setup_files = dir('setup_*.m');
    if ~isempty(setup_files)
        for i = 1:numel(setup_files)
            setup_name = erase(setup_files(i).name, '.m');
            fprintf('  [1/4] Running setup: %s\n', setup_files(i).name);
            try
                run(setup_name);
                fprintf('     Setup complete\n');
            catch e
                fprintf('     Setup warning: %s\n', e.message);
            end
        end
    else
        fprintf('  [1/4] No setup script found - using model defaults\n');
    end

    % Get timing info
    stop_time = str2double(get_param(model_name, 'StopTime'));
    dt_str    = get_param(model_name, 'FixedStep');
    if strcmp(dt_str, 'auto') || isnan(str2double(dt_str))
        dt = 0.01;
    else
        dt = str2double(dt_str);
    end
    fprintf('     Stop: %gs  Step: %gs\n', stop_time, dt);

    % Step 2: Run simulation
    fprintf('  [2/4] Running simulation...\n');
    simOut  = sim(model_name, 'ReturnWorkspaceOutputs', 'on');
    ref_csv = sprintf('%s_ref.csv', model_name);
    save_reference_csv(simOut, ref_csv, model_name);
    fprintf('     Reference saved: %s\n', ref_csv);

    % Step 3: Export FMU
    fprintf('  [3/4] Exporting FMU...\n');
    exportToFMU2CS(model_name, 'SaveDirectory', model_dir);
    fprintf('     FMU exported\n');

    % Step 4: Generate JSON
    fprintf('  [4/4] Generating JSON...\n');
    generate_json(model_name, model_dir, stop_time, dt, ref_csv);
    fprintf('     JSON generated\n');

    close_system(model_name, 0);

catch e
    try, close_system(model_name, 0); catch, end
    cd(original_dir);
    rethrow(e);
end

cd(original_dir);
end


% =============================================================
function save_reference_csv(simOut, csv_path, model_name)
% Handles all MATLAB output formats:
%   Format A: logsout (Signal Logging enabled in Simulink)
%   Format B: yout as Simulink.SimulationData.Dataset (modern)
%   Format C: yout as plain matrix (older MATLAB)

% ── Format A: logsout ────────────────────────────────────────
try
    if isprop(simOut, 'logsout') && ~isempty(simOut.logsout)
        logs  = simOut.logsout;
        names = logs.getElementNames();
        if ~isempty(names)
            first = logs.getElement(names{1});
            time  = first.Values.Time(:);
            fid   = fopen(csv_path, 'w');
            fprintf(fid, 'time');
            for k = 1:numel(names)
                fprintf(fid, ',%s', names{k});
            end
            fprintf(fid, '\r\n');
            for row = 1:length(time)
                fprintf(fid, '%.10f', time(row));
                for k = 1:numel(names)
                    sig = logs.getElement(names{k});
                    val = sig.Values.Data(row);
                    fprintf(fid, ',%.10f', val);
                end
                fprintf(fid, '\r\n');
            end
            fclose(fid);
            fprintf('     Format A: %d signals, %d rows\n', numel(names), length(time));
            return
        end
    end
catch e
    fprintf('     Format A failed: %s\n', e.message);
end

% ── Format B/C: yout ─────────────────────────────────────────
try
    % Get time
    if isprop(simOut, 'tout') && ~isempty(simOut.tout)
        time = simOut.tout(:);
    else
        error('No time data in simOut');
    end

    % Get output
    if ~isprop(simOut, 'yout') || isempty(simOut.yout)
        error('No yout in simOut');
    end

    raw = simOut.yout;

    % Handle Dataset format (modern MATLAB)
    % Uses yout{1}.Values.Data -- same as working old .m scripts
    if isa(raw, 'Simulink.SimulationData.Dataset')
        elem     = raw{1};              % first signal (same as yout{1})
        data     = elem.Values.Data(:); % same as yout{1}.Values.Data
        time     = elem.Values.Time(:);
        % Try to get signal name
        try
            names    = raw.getElementNames();
            col_name = names{1};
        catch
            col_name = 'y';
        end
        fprintf('     Format B: Dataset yout{1}.Values.Data, col=%s\n', col_name);
    else
        % Plain matrix (older MATLAB)
        data     = raw(:, 1);
        col_name = 'y';
        fprintf('     Format C: plain matrix\n');
    end

    % Write CSV
    min_len = min(length(time), length(data));
    fid = fopen(csv_path, 'w');
    fprintf(fid, 'time,%s\r\n', col_name);
    for row = 1:min_len
        fprintf(fid, '%.10f,%.10f\r\n', time(row), data(row));
    end
    fclose(fid);
    fprintf('     Saved %d rows\n', min_len);
    return

catch e
    fprintf('     Format B/C failed: %s\n', e.message);
end

% ── All formats failed ────────────────────────────────────────
error(['Could not save reference CSV for %s.\n' ...
       'Please enable Signal Logging in Simulink:\n' ...
       '  Right-click output signal wire -> Log Selected Signals'], ...
       model_name);
end


% =============================================================
function generate_json(model_name, model_dir, stop_time, dt, ref_csv)

step_blocks = find_system(model_name, 'BlockType', 'Step');
sine_blocks = find_system(model_name, 'BlockType', 'SineWave');
ramp_blocks = find_system(model_name, 'BlockType', 'Ramp');
out_blocks  = find_system(model_name, 'BlockType', 'Outport');

components  = struct();
connections = {};

% Step blocks
if ~isempty(step_blocks)
    ports = struct();
    for i = 1:numel(step_blocks)
        pname = clean_name(get_param(step_blocks{i}, 'Name'));
        try
            iv  = str2double(get_param(step_blocks{i}, 'Before'));
            sv  = str2double(get_param(step_blocks{i}, 'After'));
            st  = str2double(get_param(step_blocks{i}, 'Time'));
            if isnan(iv), iv = 0; end
            if isnan(sv), sv = 1; end
            if isnan(st), st = 0; end
        catch
            iv = 0; sv = 1; st = 0;
        end
        ports.(pname) = struct('initial', iv, 'step', sv, 'step_time', st);
        connections{end+1} = conn('step_source', pname, 'fmu', pname);
    end
    components.step_source = struct('type', 'step', 'ports', ports);
end

% Sine blocks
if ~isempty(sine_blocks)
    ports = struct();
    for i = 1:numel(sine_blocks)
        pname = clean_name(get_param(sine_blocks{i}, 'Name'));
        try
            amp  = str2double(get_param(sine_blocks{i}, 'Amplitude'));
            freq = str2double(get_param(sine_blocks{i}, 'Frequency'));
            ph   = str2double(get_param(sine_blocks{i}, 'Phase'));
            bi   = str2double(get_param(sine_blocks{i}, 'Bias'));
            if isnan(amp),  amp  = 1; end
            if isnan(freq), freq = 1; end
            if isnan(ph),   ph   = 0; end
            if isnan(bi),   bi   = 0; end
        catch
            amp = 1; freq = 1; ph = 0; bi = 0;
        end
        ports.(pname) = struct('amplitude', amp, 'frequency', freq/(2*pi), ...
                               'phase', ph, 'bias', bi);
        connections{end+1} = conn('sine_source', pname, 'fmu', pname);
    end
    components.sine_source = struct('type', 'sine', 'ports', ports);
end

% FMU
fmu_files = dir(fullfile(model_dir, '*.fmu'));
if ~isempty(fmu_files)
    fmu_file = fmu_files(1).name;
else
    fmu_file = sprintf('%s.fmu', model_name);
end
components.fmu = struct('type', 'fmu', 'file', fmu_file);

% Logger - use same signal names as reference CSV
[~, ref_name, ~] = fileparts(ref_csv);
results_file = sprintf('results_%s.csv', model_name);
components.log = struct('type', 'logger', 'file', results_file);

% Wire outputs to logger
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
