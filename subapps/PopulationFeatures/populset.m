function populopt = populset(varargin)
%POPULSET This function generate tracker options for PopulationAnalyzer,
% whose behaviour looks like optimset

%                            model      needed parameters identity
populopt = struct("diffusion",     ["CA", "CV"], ...
                  "preference",    ["CA","CV","HD","BC"]);
end

