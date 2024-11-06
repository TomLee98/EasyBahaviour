classdef EBKernel
    %EBKERNEL This class defines an EBKernel object, which accept <devices>
    % and <experiment>, and it will control <devices> under <experiment>
    % workflow
    
    properties(Access = private)
        devices     (1,1)       % devices dictionary, with {camera, daq_device, pressure_controller, flowmeter}
        experiment  (1,1)       
    end
    
    methods
        function this = EBKernel(dev, eprm)
            %EBKERNEL A Constructor
            arguments
                dev     (1,1)   dictionary
                eprm    (1,1)                   =   0
            end

            this.devices = dev;
            this.experiment = eprm;
        end
    end

    methods(Access = ?EasyBehaviour)
        function run(this, delay_fi)
            %TODO: pipeline uses experiment defination

            % turn DAQ device on
            this.devices{"daq_device"}.Interpret();
            this.devices{"daq_device"}.Run();

            % turn on camera
            duration = this.devices{"daq_device"}.Duration;
            this.devices{"camera"}.Acquire(duration(end) + delay_fi);

            % live
            hImage = image(zeros(this.devices{"camera"}.ROIHeight, ...
                                 this.devices{"camera"}.ROIWidth));
            while this.devices{"camera"}.IsRunning
                frame = this.devices{"camera"}.GetCurrentFrame();
                hImage.CData = frame{1};
                pause(0.1);         % approximate 10 Hz
            end
        end

        function stop(this)

        end

        function abort(this)

        end

        function pause(this)

        end

        function recover(this)
            
        end
    end
end

