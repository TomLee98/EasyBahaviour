function population = populset(varargin)
%POPULSET This function generate tracker options for PopulationAnalyzer,
% whose behaviour looks like optimset

%                            model      needed parameters identity
population_option = struct("diffusion",     ["CA", "CV"], ...
                           "preference",    ["CA","CV","HD","BC"]);
end

