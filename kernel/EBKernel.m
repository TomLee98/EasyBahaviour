classdef EBKernel < handle
    %EBKERNEL This class defines an EBKernel object, which accept <devices>
    % and <experiment>, and it will control <devices> under <experiment>
    % workflow
    % Note that kernel only provides the basic properties and function for
    % better performance

    properties(Access = public, Dependent)
        Devices             % ___/get, 1-by-1 dictionary
        LeftTime            % ___/get, 1-by-1 double, left time before stop recording, seconds
        Status              % ___/get, 1-by-2 EBStatus, with [DeviceStatus, KernelStatus]
        Tasks               % ___/get, n-by-2 table, with 
        TotalTime           % ___/get, 1-by-1 double, total experiment time, seconds
    end
    
    properties(Access = private)
        body        (1,1)
        devices     (1,1)   dictionary = dictionary()   % devices dictionary, with 
                                                        % {camera, daq_device, pressure_controller, flowmeter}
        experiment  (1,1)  
        start_time  (1,1)   uint64  = 0
        duration    (1,1)   double  = 0
    end
    
    methods
        function this = EBKernel(ctnr, eprm)
            %EBKERNEL A Constructor
            arguments
                ctnr    (1,1)   EasyBehaviour                   % caller
                eprm    (1,1)                   =   0           % communication defination
            end

            this.body = ctnr;
            this.experiment = eprm;
        end

        function delete(this)
            % hardware disconnect
            if this.devices.isConfigured
                for ky = this.devices.keys("uniform")'
                    if this.devices{ky}.IsConnected
                        delete(this.devices{ky});       % call object delete
                    end
                end
            end

            % experiment clean
            %

            clear("this");
        end

        %% Devices Getter
        function value = get.Devices(this)
            value = this.devices;
        end

        %% LeftTime Getter
        function value = get.LeftTime(this)
            if this.duration == 0
                value = nan;
            else
                value = this.duration - toc(this.start_time);
            end
        end

        %% Status Getter
        function value = get.Status(this)
            % empty device
            if ~this.devices.isConfigured
                value = [EBStatus.DEVICE_UNREADY, EBStatus.KERNEL_UNREADY];
                return;
            end

            dev_status = true;
            for ky = this.devices.keys("uniform")'
                dev_status = (dev_status ...
                    && this.devices{ky}.IsConnected);
            end
            if dev_status, dev_status = EBStatus.DEVICE_READY; 
            else, dev_status = EBStatus.DEVICE_UNREADY;
            end

            if dev_status == EBStatus.DEVICE_READY
                if this.devices{"camera"}.IsRunning
                    value = [EBStatus.DEVICE_READY, EBStatus.KERNEL_RUNNING];
                else
                    value = [EBStatus.DEVICE_READY, EBStatus.KERNEL_READY];
                end
            else
                % at least one device is not connected
                value = [EBStatus.DEVICE_UNREADY, EBStatus.KERNEL_UNREADY];
            end
        end

        %% Tasks Getter
        function value = get.Tasks(this)
            % tasks as table, with [code, mixing]
            if isKey(this.devices, "daq_device")
                value = this.devices{"daq_device"}.TaskTable;
            else
                value = [];
            end
        end

        %% TotalTime Getter
        function value = get.TotalTime(this)
            if this.duration == 0
                value = nan;
            else
                value = this.duration;
            end
        end
    end

    methods(Access = ?EasyBehaviour)
        function add_device(this, dev)
            arguments
                this
                dev     (1,1)   dictionary
            end

            if this.devices.isConfigured
                if isKey(this.devices, "camera") ...
                        && this.devices{"camera"}.IsConnected ...
                        && this.devices{"camera"}.IsRunning
                    throw(MException("EBKernel:invalidAccess", ...
                        "EBKernel does not support hot swap."));
                end
            end
            
            % replace devices
            this.devices = dev;

            % get possible duration
            if isKey(this.devices, "daq_device") ...
                    && this.devices{"daq_device"}.IsConnected
                timeseq = this.devices{"daq_device"}.Duration;
                this.duration = timeseq(end);
            end
        end

        function update_experiment(this, eprm)
            arguments
                this
                eprm     (1,1)   dictionary
            end

            if isKey(this.devices, "camera") ...
                    && this.devices{"camera"}.IsConnected ...
                    && this.devices{"camera"}.IsRunning
                throw(MException("EBKernel:invalidAccess", ...
                    "EBKernel does not support hot experiment modifying."));
            else
                % replace experiment
                this.experiment = eprm;
            end
        end

        function run(this)
            %TODO: pipeline uses experiment defination

            %% turn on DAQ device (first of all)
            this.devices{"daq_device"}.Run();   % waitfor camera switching

            %% turn on camera and acquire right now
            this.devices{"camera"}.Acquire(this.duration);

            this.start_time = tic; % set the begin time point

            % live
            hImage = image(zeros(this.devices{"camera"}.ROIHeight, ...
                                 this.devices{"camera"}.ROIWidth));
            colormap(gca, "gray");
            while this.devices{"camera"}.IsRunning
                t = tic;
                frame = this.devices{"camera"}.GetCurrentFrame();
                hImage.CData = frame{1};
                pause(0.1-toc(t));         % approximate 10 Hz
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

