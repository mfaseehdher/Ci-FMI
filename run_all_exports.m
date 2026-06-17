function run_all_exports(experiments_dir)
% RUN_ALL_EXPORTS
% For each .slx model: run setup, simulate, save reference CSV, export FMU, write JSON.
% Matches the approach of the original working per-model scripts.

if nargin < 1
    experiments_dir = 'experiments';
end

fprintf('================================================\n');
fprintf('  MATLAB Export Pipeline\n');
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
    % Clean base workspace between models to prevent leakage
    evalin('base', 'clear t u m b K J R L A B C D M1 M2 K1 K2 b1 b2 g d');
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
    % Run the setup script for THIS model only.
    % Each folder must contain exactly ONE setup_*.m file.
    % If multiple exist (stale files), this is an error.
    setup_files = dir('setup_*.m');
    if isempty(setup_files)
        error('No setup_*.m found in %s', model_dir);
    end
    if numel(setup_files) > 1
        names = strjoin({setup_files.name}, ', ');
        error(['Multiple setup files found in %s: %s\n' ...
               'Each model folder must have exactly ONE setup file.'], ...
               model_dir, names);
    end
    setup_name = erase(setup_files(1).name, '.m');
    fprintf('  [1/4] Running setup: %s\n', setup_files(1).name);
    run(setup_name);

    % Simulation -- model is already loaded and configured by setup.
    % Use plain sim() so tout/yout land in base workspace,
    % exactly like the original working scripts.
    fprintf('  [2/4] Running simulation...\n');
    sim(model_name);

    % Extract from base workspace (set by sim)
    t_out = evalin('base', 'tout');
    raw   = evalin('base', 'yout');

    if isa(raw, 'Simulink.SimulationData.Dataset')
        out = raw{1}.Values.Data(:);
    elseif isnumeric(raw)
        out = raw(:, 1);
    else
        error('Unrecognized yout type');
    end

    % Save reference CSV
    ref_csv = sprintf('%s_ref.csv', model_name);
    min_len = min(length(t_out), length(out));
    fid = fopen(ref_csv, 'w');
    fprintf(fid, 'time,output\r\n');
    for row = 1:min_len
        fprintf(fid, '%.10f,%.10f\r\n', t_out(row), out(row));
    end
    fclose(fid);
    fprintf('     Reference saved: %s (%d rows)\n', ref_csv, min_len);

    % Export FMU
    fprintf('  [3/4] Exporting FMU...\n');
    exportToFMU2CS(model_name, 'SaveDirectory', model_dir);
    fprintf('     FMU exported\n');

    % Generate JSON
    fprintf('  [4/4] Generating JSON...\n');
    stop_time = str2double(get_param(model_name, 'StopTime'));
    dt        = 0.01;
    generate_json(model_name, model_dir, stop_time, dt);
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
function generate_json(model_name, model_dir, stop_time, dt)

out_blocks = find_system(model_name, 'BlockType', 'Outport');
in_blocks  = find_system(model_name, 'BlockType', 'Inport');

components  = struct();
connections = {};

% Use a step source feeding each inport (input was [t,u] = constant)
if ~isempty(in_blocks)
    ports = struct();
    for i = 1:numel(in_blocks)
        pname = clean_name(get_param(in_blocks{i}, 'Name'));
        ports.(pname) = struct('initial', 0, 'step', 1, 'step_time', 0);
        connections{end+1} = conn('stim', pname, 'fmu', pname);
    end
    components.stim = struct('type', 'step', 'ports', ports);
end

% FMU
fmu_files = dir(fullfile(model_dir, '*.fmu'));
if ~isempty(fmu_files)
    fmu_file = fmu_files(1).name;
else
    fmu_file = sprintf('%s.fmu', model_name);
end
components.fmu = struct('type', 'fmu', 'file', fmu_file);

% Logger
components.log = struct('type', 'logger', ...
    'file', sprintf('results_%s.csv', model_name));

% Wire outputs to logger
for i = 1:numel(out_blocks)
    pname = clean_name(get_param(out_blocks{i}, 'Name'));
    connections{end+1} = conn('fmu', pname, 'log', pname);
end

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
