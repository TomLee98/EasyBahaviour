function paramopt = paramset(varargin)
%PARAMSET This function generate parameterization options for Parameterizer,
% whose behaviour looks like optimset

%                                          operator  options
paramopt = struct("backbone_curvature",     {{@bc, {}}}, ...
                  "center_acceleration",    {{@ca, {}}}, ...
                  "center_position",        {{@cp, {}}}, ...
                  "center_velocity",        {{@cv, {}}}, ...
                  "head_direction",         {{@hd, {}}}, ...
                  "segment_acceleration",   {{@sa, {}}}, ...
                  "segment_velocity",       {{@sv, {}}}, ...
                  "tail_direction",         {{@td, {}}});
end

