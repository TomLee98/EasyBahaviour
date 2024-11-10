classdef EBKernel < handle
    %EBKERNEL This class defines an EBKernel object, which accept <devices>
    % and <experiment>, and it will control <devices> under <experiment>
    % workflow
    % Note that kernel only provides the basic properties and function for
    % better performance

    properties (Constant, Hidden)
        DAQ_DELAY = 0.2
    end

    properties(Access = public, Dependent)
        Devices             % ___/get, 1-by-1 dictionary
        Frames              % ___/get, 1-by-1 Images object
        FramesInfo          % ___/get, 0-by-13 or 1-by-13 table
        LeftTime            % ___/get, 1-by-1 double, left time before stop recording, seconds
        Scale               % set/get, 1-by-1 struct, with [xRes, yRes, resUnit]
        Status              % ___/get, 1-by-3 EBStatus, with [DeviceStatus, KernelStatus, TaskStatus]
        Tasks               % ___/get, n-by-2 table, with 
        TotalTime           % ___/get, 1-by-1 double, total experiment time, seconds
    end
    
    properties(Access = private)
        body        (1,1)
        devices     (1,1)   dictionary = dictionary()   % devices dictionary, with 
                                                        % {camera, daq_device, pressure_controller, flowmeter}
        experiment  (1,1)  
        scale       (1,1)   struct = struct("xRes",0.1, "yRes",0.1, "resUnit","mm");
        start_time  (1,1)   uint64  = 0
        duration    (1,1)   double  = 0
        adjust_t    (1,1)   double  = 0                 % adjust time because of kernel using
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
                    if isobject(this.devices{ky})
                        this.devices{ky}.delete();       % call object delete
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

        %% Frames Getter
        function value = get.Frames(this)
            if this.devices.isConfigured ...
                    && this.devices{"camera"}.IsConnected
                value = this.devices{"camera"}.ImagesBuffer;
            else
                value = Images.empty();
            end
        end

        %% FramesInfo Getter
        function value = get.FramesInfo(this)
            if this.devices.isConfigured ...
                    && this.devices{"camera"}.IsConnected
                value = table('Size', [1, 13], ...
                    'VariableTypes', {'double','double','double','double','double', ...
                    'double','double','double','double','double','string','string','datetime'}, ...
                    'VariableNames', {'width', 'height', 'xOffset', 'yOffset', 'xBinning', ...
                    'yBinning', 'xResolution','yResolution', 'frameRate', 'bitDepth', ...
                    'deviceModel', 'resolutionUnit','dateTime'});

                value.width = this.devices{"camera"}.ROIWidth;
                value.height = this.devices{"camera"}.ROIHeight;
                value.xOffset = this.devices{"camera"}.OffsetX;
                value.yOffset = this.devices{"camera"}.OffsetY;
                value.xBinning = this.devices{"camera"}.BinningHorizontal;

                value.yBinning = this.devices{"camera"}.BinningVertical;
                value.xResolution = this.scale.xRes;
                value.yResolution = this.scale.yRes;
                value.frameRate = this.devices{"camera"}.AcquireFrameRate;
                value.bitDepth = this.devices{"camera"}.BitDepth;

                value.deviceModel = this.devices{"camera"}.DeviceModelName;
                value.resolutionUnit = this.scale.resUnit;
                value.dateTime = this.devices{"camera"}.DateTime;
            else
                value = table('Size', [0, 13], ...
                    'VariableTypes', {'double','double','double','double','double', ...
                    'double','double','double','double','double','string','string','datetime'}, ...
                    'VariableNames', {'width', 'height', 'xOffset', 'yOffset', 'xBinning', ...
                    'yBinning', 'xResolution','yResolution', 'frameRate', 'bitDepth', ...
                    'deviceModel', 'resolutionUnit','dateTime'});
            end
        end

        %% LeftTime Getter
        function value = get.LeftTime(this)
            if this.devices.isConfigured ...
                    && this.devices{"daq_device"}.IsConnected
                if this.devices{"camera"}.IsRunning ...
                        && (this.start_time ~= 0)
                    value = max(0, this.duration - toc(this.start_time) + this.DAQ_DELAY);
                else
                    value = this.duration;
                end
            else
                value = nan;
            end
        end

        %% Scale Getter & Setter
        function value = get.Scale(this)
            value = this.scale;
        end

        function set.Scale(this, value)
            arguments
                this
                value   (1,1)   struct
            end

            if ~isempty(setdiff(string(fieldnames(value)), ["xRes","yRes","resUnit"]))
                throw(MException("EBKernel:invalidScale", "Scale must be struct scalar with " + ...
                    "xRes, yRes and resUnit."));
            else
                this.scale = value;
            end
        end

        %% Status Getter
        function value = get.Status(this)
            % empty device
            if ~this.devices.isConfigured
                value = [EBStatus.DEVICE_UNREADY, EBStatus.KERNEL_UNREADY, EBStatus.TASK_NONE];
                return;
            end

            dev_status = true;
            for ky = this.devices.keys("uniform")'
                dev_status = (dev_status ...
                    && this.devices{ky}.IsConnected);
            end
            if dev_status
                if this.devices{"camera"}.IsRunning ...
                        || this.devices{"camera"}.IsSuspending
                    value = [EBStatus.DEVICE_READY, EBStatus.KERNEL_RUNNING, EBStatus.TASK_RUNNING];
                else
                    if ~this.devices{"camera"}.ImagesBuffer.IsEmpty
                        value = [EBStatus.DEVICE_READY, EBStatus.KERNEL_READY, EBStatus.TASK_DONE];
                    else
                        value = [EBStatus.DEVICE_READY, EBStatus.KERNEL_READY, EBStatus.TASK_NONE];
                    end
                end 
            else
                value = [EBStatus.DEVICE_UNREADY, EBStatus.KERNEL_UNREADY, EBStatus.TASK_NONE];
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

            % live
            figure("Name", "Video Player - Waiting)");
            hImage = image(zeros(this.devices{"camera"}.ROIHeight, ...
                            this.devices{"camera"}.ROIWidth));
            colormap(gca, "gray");
            drawnow
            
            %% turn on DAQ device (first of all)
            this.devices{"daq_device"}.Run();   % waitfor camera switching

            %% turn on camera and acquire right now
            this.devices{"camera"}.Acquire(this.duration + this.DAQ_DELAY);

            pause(0.2);
            set(gcf, "Name", "Video Player - Running");
            
            this.start_time = this.devices{"camera"}.StartTime;

            while this.devices{"camera"}.IsRunning
                frame = this.devices{"camera"}.GetCurrentFrame();
                hImage.CData = frame{1};
                pause(0.05);
            end

            close(gcf);
            this.start_time = 0;

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

