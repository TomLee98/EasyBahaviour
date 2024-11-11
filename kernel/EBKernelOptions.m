classdef EBKernelOptions < handle
    %EBKERNELOPTIONS This class define kernel running options
    
    properties(Access = public, Dependent)
        %% Scale Properties
        XResolution                 % set/get, 1-by-1 positive double, resolution at x direction
        YResolution                 % set/get, 1-by-1 positive double, resolution at y direction
        ResolutionUnit              % set/get, 1-by-1 string, real world length unit, in [um, mm, cm, inch]

        %% Tracker Properties
        DetectFeature               % set/get, 
        FeatureMixModel             % set/get, 
        FeatureSampling             % set/get,
        SemanticsClassifier         % set/get,
        MotionPredictor             % set/get,
        ObjectMatcher               % set/get, 

        %% Parameterizer Properties
        BackboneCurvatureOperator   % set/get,
        CenterAccelarationOperator  % set/get,
        CenterVelocityOperator      % set/get

        %% Population Properties
        %
    end

    properties(Access=private, Hidden)
        option              % 1-by-1 dictionary, key in [scale, tracker, parameterizer, population]
    end
    
    methods
        function this = EBKernelOptions(varargin)
            %EBKERNELOPTIONS A Constructor
            % read Name-Value pair
            p = inputParser;
            p.StructExpand = false;

            this.option = EBKernelOptions.defaultOptions();

            addParameter(p, "Scale", this.option("scale"), @(x)validatescale(x));
            addParameter(p, "Tracker", this.option("tracker"), @(x)validatetracker(x));
            addParameter(p, "Parameterizer", this.option("parameterizer"), @(x)validateparameterizer(x));
            addParameter(p, "Population", this.option("population"), @(x)validatepopulation(x));

            parse(p, varargin{:});
        end

        %% XResolution Getter & Setter
        function value = get.XResolution(this)
            value = this.option("scale").xRes;
        end

        function set.XResolution(this, value)
            arguments
                this
                value   (1,1)   double  {mustBePositive}
            end

            this.option("scale").xRes = value;
        end

        %% YResolution Getter & Setter
        function value = get.YResolution(this)
            value = this.option("scale").yRes;
        end

        function set.YResolution(this, value)
            arguments
                this
                value   (1,1)   double  {mustBePositive}
            end

            this.option("scale").yRes = value;
        end

        %% ResolutionUnit Getter & Setter
        function value = get.ResolutionUnit(this)
            value = this.option("scale").resUnit;
        end

        function set.ResolutionUnit(this, value)
            arguments
                this
                value   (1,1)   string  {mustBeMember(value, ["um","mm","cm","inch"])}
            end

            this.option("scale").resUnit = value;
        end

    end

    methods(Static)
        function options = defaultOptions()
            %% Scale Options
            scale_option = struct("xRes",       0.1, ...
                                  "yRes",       0.1, ...
                                  "resUnit",    "mm");

            %% Tracker Options
            tracker_option = struct("feature",      ["SURF","HOG"], ...
                                    "mix_model",    "augment", ...
                                    "sampling",     10, ...
                                    "classifter",   "SVM", ...
                                    "predictor",    "KF", ...
                                    "matcher",      "KM");

            %% Parameterizer Options
            %                                                    operator  options
            parameterizer_option = struct("backbone_curvature",     {{@bc, {}}}, ...
                                          "center_acceleration",    {{@ca, {}}}, ...
                                          "center_velocity",        {{@cv, {}}}, ...
                                          "head_direction",         {{@hd, {}}}, ...
                                          "segment_acceleration",   {{@sa, {}}}, ...
                                          "segment_velocity",       {{@sv, {}}}, ...
                                          "tail_direction",         {{@td, {}}});

            %% PFA(Population Features Analysis) Options
            %                            model      needed parameters identity
            population_option = struct("diffusion",     ["CA", "CV"], ...
                                       "preference",    ["CA","CV","HD","BC"]);

            options = dictionary("scale",           scale_option, ...
                                 "tracker",         tracker_option, ...
                                 "parameterizer",   parameterizer_option, ...
                                 "population",      population_option);
        end
    end
end

function validatescale(A)
if ~isstruct(A)
    throw(MException("EBKernelOptions:invalidScaleOption", ...
        "Option must be a struct."));
end
if ~all(ismember(string(fieldnames(A)), ["xRes", "yRes", "resUnit"]))
    throw(MException("EBKernelOptions:invalidScaleKey", ...
        "Unsupported key in scale option."));
end
end

function validatetracker(A)
if ~isstruct(A)
    throw(MException("EBKernelOptions:invalidTrackerOption", ...
        "Option must be a struct."));
end
if ~all(ismember(string(fieldnames(A)), ...
        ["feature", "mix_model", "sampling", "classifier", "predictor", "matcher"]))
    throw(MException("EBKernelOptions:invalidTrackerKey", ...
        "Unsupported key in tracker option."));
end
end

function validateparameterizer(A)
if ~isstruct(A)
    throw(MException("EBKernelOptions:invalidParameterizerOption", ...
        "Option must be a struct."));
end
if ~all(ismember(string(fieldnames(A)), ["backbone_curvature", "center_acceleration", ...
        "center_velocity", "head_direction", "segment_acceleration", ...
        "segment_velocity", "tail_direction"]))
    throw(MException("EBKernelOptions:invalidParameterizerKey", ...
        "Unsupported key in parameterizer option."));
end
end

function validatepopulation(A)
if ~isstruct(A)
    throw(MException("EBKernelOptions:invalidPopulationOption", ...
        "Option must be a struct."));
end
if ~all(ismember(string(fieldnames(A)), ["diffusion", "preference"]))
    throw(MException("EBKernelOptions:invalidPopulationKey", ...
        "Unsupported key in population option."));
end
end
