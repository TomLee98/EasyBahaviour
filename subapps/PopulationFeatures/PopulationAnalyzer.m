classdef PopulationAnalyzer
    %POPULATIONANALYZER 此处显示有关此类的摘要
    %   此处显示详细说明
    
    properties(Access = private)
        options
    end
    
    methods
        function this = PopulationAnalyzer(options_)
            arguments
                options_    (1,1)   struct  = struct("diffusion",     ["CA", "CV"], ...
                                                     "preference",    ["CA","CV","HD","BC"]);
            end
            
            this.options = options_;
        end
    end
end

