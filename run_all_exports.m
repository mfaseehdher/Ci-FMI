function run_all_exports(experiments_dir)
% RUN_ALL_EXPORTS
% Finds all .slx files and for each model:
%   1. Changes to model directory
%   2. Runs setup_*.m which loads model, sets params, runs sim, saves CSV
%   3. Exports FMU
%
% The setup files handle everything up to and including simulation.
% This function handles MATLAB reference generation and FMU export.
% Python generates normal single-FMU experiment JSON files later.

if nargin < 1
    experiments_dir = 'experiments';
end

fprintf('================================================\n');
fprintf('  MATLAB Export Pipeline\n');
fprintf('================================================\n\n');

coupled_markers = dir(fullfile(experiments_dir, '**', 'coupled_experiment.json'));
coupled_dirs = unique({coupled_markers.folder});

model_files = [dir(fullfile(experiments_dir, '**', '*.slx')); ...
               dir(fullfile(experiments_dir, '**', '*.mdl'))];
slx_files = filter_standard_models(model_files, coupled_dirs);

if isempty(slx_files) && isempty(coupled_dirs)
    error('No standard or coupled experiments found in %s', experiments_dir);
end
fprintf('Found %d standard model(s)\n', numel(slx_files));
fprintf('Found %d coupled experiment(s)\n\n', numel(coupled_dirs));

passed = {}; failed = {};

for i = 1:numel(slx_files)
    model_dir  = slx_files(i).folder;
    [~, model_name, ~] = fileparts(slx_files(i).name);
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

for i = 1:numel(coupled_dirs)
    model_dir = coupled_dirs{i};
    [~, model_name] = fileparts(model_dir);
    fprintf('--- Coupled [%d/%d] %s ---\n', i, numel(coupled_dirs), model_name);
    try
        process_coupled_experiment(model_dir);
        passed{end+1} = sprintf('%s (coupled)', model_name);
        fprintf('[%s] SUCCESS\n\n', model_name);
    catch e
        failed{end+1} = sprintf('%s (coupled)', model_name);
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
function filtered = filter_standard_models(model_files, coupled_dirs)

if isempty(coupled_dirs)
    filtered = model_files;
    return;
end

keep = true(size(model_files));
for i = 1:numel(model_files)
    for j = 1:numel(coupled_dirs)
        if strcmpi(model_files(i).folder, coupled_dirs{j})
            keep(i) = false;
            break;
        end
    end
end

filtered = model_files(keep);
end


% =============================================================
function process_coupled_experiment(model_dir)

original_dir = pwd;
addpath(original_dir);
cd(model_dir);

try
    setup_files = dir('setup_*.m');
    if isempty(setup_files)
        error('No setup_*.m found in coupled experiment %s', model_dir);
    end

    setup_script = fullfile(model_dir, setup_files(1).name);
    fprintf('  [1/3] Running coupled setup: %s\n', setup_files(1).name);
    evalin('base', sprintf("run('%s')", strrep(setup_script, '\', '\\')));

    ref_files = dir('*_ref.csv');
    if isempty(ref_files)
        error('Coupled setup did not produce a reference CSV');
    end
    fprintf('  [2/3] Reference CSV: %s\n', ref_files(1).name);

    fmu_files = dir('*.fmu');
    if numel(fmu_files) < 2
        error('Coupled setup must export at least two FMUs');
    end

    json_files = dir('*.json');
    json_files = json_files(~strcmp({json_files.name}, 'coupled_experiment.json'));
    if isempty(json_files)
        error('Coupled setup did not produce a runnable experiment JSON');
    end
    fprintf('  [3/3] Coupled JSON: %s, FMUs: %d\n', ...
        json_files(1).name, numel(fmu_files));

    try, bdclose('all'); catch, end

catch e
    try, bdclose('all'); catch, end
    cd(original_dir);
    rethrow(e);
end

cd(original_dir);
end


% =============================================================
function process_one_model(model_name, model_dir)

original_dir = pwd;
addpath(original_dir);
cd(model_dir);

try
    % Find and run setup script
    setup_files = dir('setup_*.m');
    if isempty(setup_files)
        error('No setup_*.m found in %s', model_dir);
    end

    % Run setup as a script in base workspace.
    % Setup loads model, configures it, runs sim, saves reference CSV.
    setup_script = fullfile(model_dir, setup_files(1).name);
    fprintf('  [1/4] Running setup: %s\n', setup_files(1).name);
    evalin('base', sprintf("run('%s')", strrep(setup_script, '\', '\\')));

    % Verify reference CSV was created by setup
    csv_files = dir('*_ref.csv');
    if isempty(csv_files)
        error('Setup did not produce a reference CSV');
    end
    fprintf('  [2/4] Reference CSV: %s\n', csv_files(1).name);

    % Export FMU
    fprintf('  [3/3] Exporting FMU...\n');
    exportToFMU2CS(model_name, 'SaveDirectory', model_dir);
    fprintf('     FMU exported\n');

    close_system(model_name, 0);

catch e
    try, close_system(model_name, 0); catch, end
    cd(original_dir);
    rethrow(e);
end

cd(original_dir);
end


% =============================================================
function ref_csv = save_reference_csv(simOut, model_name)

ref_csv = sprintf('%s_ref.csv', model_name);

try
    raw  = simOut.yout;
    time = simOut.tout(:);
    if isa(raw, 'Simulink.SimulationData.Dataset')
        out = raw{1}.Values.Data(:);
    else
        out = raw(:,1);
    end
    n   = min(length(time), length(out));
    fid = fopen(ref_csv, 'w');
    fprintf(fid, 'time,output\r\n');
    for row = 1:n
        fprintf(fid, '%.10f,%.10f\r\n', time(row), out(row));
    end
    fclose(fid);
    fprintf('     Saved %d rows\n', n);
catch e
    error('Cannot save reference CSV: %s', e.message);
end
end


% =============================================================
function generate_json(model_name, model_dir, stop_time, dt)

fmu_file = sprintf('%s.fmu', model_name);
fmu_path = fullfile(model_dir, fmu_file);

if ~isfile(fmu_path)
    fmu_files = dir(fullfile(model_dir, '*.fmu'));
    if isempty(fmu_files)
        error('No FMU found in %s', model_dir);
    end
    fmu_file = fmu_files(1).name;
    fmu_path = fullfile(model_dir, fmu_file);
end

[input_names, output_names] = read_fmu_ports(fmu_path);
ref_signal_names = read_reference_signal_names(model_dir, model_name);

components  = struct();
connections = {};

if ~isempty(input_names)
    ports = struct();
    for i = 1:numel(input_names)
        stim_port = clean_name(input_names{i});
        ports.(stim_port) = struct('initial', 0, 'step', 1, 'step_time', 0);
        connections{end+1} = conn('stim', stim_port, 'fmu', input_names{i});
    end
    components.stim = struct('type', 'step', 'ports', ports);
end

components.fmu = struct('type', 'fmu', 'file', fmu_file);
components.log = struct('type', 'logger', ...
    'file', sprintf('results_%s.csv', model_name));

for i = 1:numel(output_names)
    log_name = output_names{i};
    if i <= numel(ref_signal_names)
        log_name = ref_signal_names{i};
    end
    connections{end+1} = conn('fmu', output_names{i}, 'log', log_name);
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


function [input_names, output_names] = read_fmu_ports(fmu_path)

tmp_dir = tempname;
mkdir(tmp_dir);
cleanup = onCleanup(@() rmdir(tmp_dir, 's'));

unzip(fmu_path, tmp_dir);
xml_path = fullfile(tmp_dir, 'modelDescription.xml');

doc = xmlread(xml_path);
vars = doc.getElementsByTagName('ScalarVariable');

input_names = {};
output_names = {};

for i = 0:vars.getLength-1
    node = vars.item(i);
    name = char(node.getAttribute('name'));
    causality = char(node.getAttribute('causality'));

    if strcmp(causality, 'input')
        input_names{end+1} = name;
    elseif strcmp(causality, 'output')
        output_names{end+1} = name;
    end
end

end


function signal_names = read_reference_signal_names(model_dir, model_name)

signal_names = {};
ref_path = fullfile(model_dir, sprintf('%s_ref.csv', model_name));

if ~isfile(ref_path)
    refs = dir(fullfile(model_dir, '*_ref.csv'));
    if isempty(refs)
        return
    end
    ref_path = fullfile(model_dir, refs(1).name);
end

fid = fopen(ref_path, 'r');
if fid < 0
    return
end

header = fgetl(fid);
fclose(fid);

if ~ischar(header)
    return
end

parts = strsplit(strtrim(header), ',');
if numel(parts) > 1
    signal_names = parts(2:end);
end

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
