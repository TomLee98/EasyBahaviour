classdef EBStatus
    %EBSTATUS This is enumeric class to define status

    properties(SetAccess=immutable, GetAccess=private, Hidden)
        R   (1,1)
        G   (1,1)
        B   (1,1)
    end
    
    methods
        function this = EBStatus(r, g, b)
            arguments
                r   (1,1)   double  {mustBeInRange(r, 0, 1)} = 0
                g   (1,1)   double  {mustBeInRange(g, 0, 1)} = 0
                b   (1,1)   double  {mustBeInRange(b, 0, 1)} = 0
            end
            this.R = r; this.G = g; this.B = b;
        end

        % only getter is valid
        function value = ToRGB(this)
            value = [this.R, this.G, this.B];
        end
    end

    enumeration
        DEVICE_READY        (0.0, 1.0, 0.0)     % device is ready
        DEVICE_UNREADY      (0.8, 0.8, 0.8)     % 
        KERNEL_UNREADY      (0.8, 0.8, 0.8)     % kernel
        KERNEL_RUNNING      (0.0, 1.0, 0.0)     % running
        KERNEL_READY        (1.0, 1.0, 0.0)     % ready before running
        KERNEL_PAUSE        (1.0, 0.0, 0.0)     % pause in running
        TASK_NONE           (0.0, 0.0, 0.0)
        TASK_RUNNING        (0.0, 1.0, 0.0)
        TASK_DONE           (1.0, 1.0, 1.0)
    end
end

