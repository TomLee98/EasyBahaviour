classdef PopulationAnalyzer < handle
    %POPULATIONANALYZER 此处显示有关此类的摘要
    %   此处显示详细说明

    properties (GetAccess = public, Dependent)
        Traces      % ___/get, 1-by-1 dictionary, <string> -> <cell>, id |-> [x1,y1,t1; x2,y2,t2; ...]
    end
    
    properties(Access = private)
        traces

        options
    end
    
    methods
        function this = PopulationAnalyzer(options_)
            arguments
                options_    (1,1)   struct  = struct("diffusion",     ["CA", "CV"], ...
                                                     "preference",    ["CA","CV","HD","BC"]);
            end

            this.traces = configureDictionary("string", "cell");
            
            this.options = options_;
        end

        %% Traces Getter
        function value = get.Traces(this)
            value = this.traces;
        end

        function delete(this)
            % ~
        end
    end

    methods (Access = public)
        function extendTrace(this, gcs)
            arguments
                this
                gcs     (1,1)   dictionary
            end

            % extend after each calling
            this.extend_trace(gcs);
        end
    end

    methods (Access = private)
        function extend_trace(this, gcs)
            %EXTRACTTRACE This function is temporary simple trace generator, just use
            % geometric center as trace point

            if  gcs.isConfigured ...
                    && gcs.numEntries > 0
                for key = gcs.keys("uniform")'
                    if this.traces.isKey(key)
                        % append record
                        this.traces{key} = [this.traces{key}; gcs{key}];
                    else
                        % create new record
                        this.traces(key) = gcs(key);
                    end
                end
            end
        end
    end

    methods (Static)
        function value = noneTrace()
            value = configureDictionary("string", "cell");
        end
    end
end

