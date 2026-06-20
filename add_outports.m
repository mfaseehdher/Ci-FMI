function add_outports(model_path, output_name)
% ADD_OUTPORTS
% Prepares a Scope-based model for FMU export by adding an Outport
% connected to the signal that currently goes to the Scope.
%
% This is a ONE-TIME model preparation step. CTMS teaching models use
% Scope blocks for display; FMU export requires Outport blocks. After
% running this once and saving, the model has a proper output interface.
%
% Usage:
%   add_outports('ccmodel', 'Velocity')
%   add_outports('ballBeam', 'BallPosition')
%   add_outports('aircraft_pitch_control', 'PitchAngle')
%
% The output_name should match the signal name in your reference CSV
% so the comparison step can match them.

if nargin < 2
    output_name = 'Output';
end

load_system(model_path);
[~, model_name, ~] = fileparts(model_path);

% Check if model already has Outports
existing_out = find_system(model_name, 'SearchDepth', 1, ...
    'BlockType', 'Outport');
if ~isempty(existing_out)
    fprintf('%s already has %d Outport(s). No change needed.\n', ...
        model_name, numel(existing_out));
    return
end

% Find scopes
scopes = find_system(model_name, 'BlockType', 'Scope');
fprintf('Found %d scope(s) in %s\n', numel(scopes), model_name);

if isempty(scopes)
    fprintf('No scopes and no outports. Cannot determine output signal.\n');
    return
end

% Use the FIRST scope's input signal as the model output
scope = scopes{1};
ph = get_param(scope, 'PortHandles');
if isempty(ph.Inport)
    error('Scope has no input port');
end

line_h = get_param(ph.Inport(1), 'Line');
if line_h == -1
    error('Scope input is not connected to any signal');
end

src_port = get_param(line_h, 'SrcPortHandle');
if src_port == -1
    error('Cannot find signal source');
end

% Position new outport to the right of the scope
scope_pos = get_param(scope, 'Position');
out_pos = [scope_pos(1)+200, scope_pos(2), ...
           scope_pos(1)+230, scope_pos(2)+30];

% Add outport with the meaningful name
out_block = sprintf('%s/%s', model_name, output_name);
add_block('simulink/Sinks/Out1', out_block, 'Position', out_pos);

% Connect signal to outport (branch from existing signal)
out_ph = get_param(out_block, 'PortHandles');
add_line(model_name, src_port, out_ph.Inport(1), 'autorouting', 'on');

fprintf('  Added Outport "%s" connected to scope signal\n', output_name);

% Configure output saving
set_param(model_name, 'SaveOutput',  'on');
set_param(model_name, 'SaveFormat',  'Dataset');

save_system(model_name);
fprintf('Saved %s with new Outport "%s"\n', model_name, output_name);
fprintf('Now re-export the FMU - it will have output "%s"\n', output_name);

end
