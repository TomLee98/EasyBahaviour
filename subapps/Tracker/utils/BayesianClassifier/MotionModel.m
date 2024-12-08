classdef MotionModel
    %MOTIONMODEL This helper class defined for BayesianMotionClassifier,
    % which store motion model and parameters

    properties(Constant)
        MODELDEF = "NOISE-MOTION"
    end
    
    properties(GetAccess = public, SetAccess=immutable)
        Vmdl
        Args
    end
    
    methods
        function this = MotionModel(vmdl_, args_)
            % A Constructor
            arguments
                vmdl_    (1,1)   string  {mustBeMember(vmdl_, ...
                            ["Brownian-Gaussian","Gamma-Gaussian"])} = "Brownian-Gaussian"
                args_    (1,1)   struct  = struct("s0",  0.25, ...
                                                  "d",   4, ...
                                                  "v1",  1.40, ...
                                                  "s1",  0.45)
            end

            this.Vmdl = vmdl_;
            this.Args = args_;
        end
    end
end

