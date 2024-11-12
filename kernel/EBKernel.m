classdef EBKernel < handle
    %EBKERNEL This class defines an EBKernel object, which accept <devices>
    % and <experiment>, and it will control <devices> under <experiment>
    % workflow
    % Note that kernel only provides the basic properties and function for
    % better performance
    % EBKernel manage two data queue: raw data()

    properties (Constant, Hidden)
        DAQ_DELAY = 0.2             % DAQ-Kernel response delay (to camera) 
    end

    properties(Access = public, Dependent)
        CurrentVideoFrame   % ___/get, 1-by-1 VideoFrame object
        Devices             % ___/get, 1-by-1 dictionary
        Feature             % set/get, 1-by-3 EBStatus array, [TrackerStatus, ParameterizerStatus, PopulationStatus]
        Frames              % ___/get, 1-by-1 Images object
        FramesInfo          % ___/get, 0-by-13 or 1-by-13 table
        IsRunning           % ___/get, 1-by-1 logical, indicate if kernel is running
        LeftTime            % ___/get, 1-by-1 double, left time before stop recording, seconds
        Option              % set/get, 1-by-1 EBKernelOption, the options for running feature
        Status              % ___/get, 1-by-3 EBStatus array, with [DeviceStatus, KernelStatus, TaskStatus]
        Tasks               % ___/get, n-by-2 table, with 
        TotalTime           % ___/get, 1-by-1 double, total experiment time, seconds
        Video               % ___/get, 1-by-1 EBVideo object
    end
    
    properties(Access = private)
        adjust_t        (1,1)   double              = 0                 % adjust time because of kernel using
        body            (1,1)                                           % container/caller, who ask kernel for update info
        devices         (1,1)   dictionary          = dictionary()      % devices dictionary
        duration        (1,1)   double              = 0                 % task duration
        feature         (1,3)   EBStatus                                % task feature, function configuration
        options         (1,1)   EBKernelOptions                         % task options
        paradigm        (1,1)   EBParadigm                              % EBParadigm object, experiment pipeline defination
        parameterizer   (1,1)   Parameterizer                           % Parameterizer object, motion parameterize
        pfanalyzer      (1,1)   PopulationAnalyzer                      % PopulationAnalyzer object, analyze population features
        start_time      (1,1)   uint64              = 0                 % kernel(camera) absolute start time from tic
        tracker         (1,1)   Tracker                                 % Tracker object, tracking object motion
        videos          (1,1)   EBVideo             = EBVideo.empty()   % video frame queue, with VideoFrame object as item   
    end
    
    methods
        function this = EBKernel(ctnr, pdgm)
            %EBKERNEL A Constructor
            arguments
                ctnr    (1,1)                  = 0              % caller
                pdgm    (1,1)   EBParadigm     = EBParadigm()   % paradigm defination
            end

            this.body = ctnr;
            this.paradigm = pdgm;

            this.videos = EBVideo.empty();
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

            % paradigm clean
            % ~

            clear("this");
        end

        %% CurrentVideoFrame Getter
        function value = get.CurrentVideoFrame(this)
            value = this.videos.GetLastFrame();
        end

        %% Devices Getter
        function value = get.Devices(this)
            value = this.devices;
        end

        %% Feature Getter & Setter
        function value = get.Feature(this)
            value = this.feature;
        end

        function set.Feature(this, value)
            arguments
                this
                value   (1,3)   EBStatus
            end

            if this.IsRunning
                throw(MException("EBKernel:invalidAccess", ...
                    "Running kernel feature is unsetable."));
            else
                this.feature = value;
            end
        end

        %% Frames Getter
        function value = get.Frames(this)
            if this.devices.isConfigured ...
                    && this.devices{"camera"}.IsConnected
                value = this.devices{"camera"}.ImagesBuffer;    % just read buffer
            else
                value = EBImages.empty();
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
                value.xResolution = this.options.XResolution;
                value.yResolution = this.options.YResolution;
                value.frameRate = this.devices{"camera"}.AcquireFrameRate;
                value.bitDepth = this.devices{"camera"}.BitDepth;

                value.deviceModel = this.devices{"camera"}.DeviceModelName;
                value.resolutionUnit = this.options.ResolutionUnit;
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

        %% IsRunning Getter
            function value = get.IsRunning(this)
                value = (this.devices.isConfigured ...
                    && isKey(this.devices, "camera") ...
                    && this.devices{"camera"}.IsConnected ...
                    && this.devices{"camera"}.IsRunning);
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

        %% Option Getter & Setter
        function value = get.Option(this)
            value = this.options;
        end

        function set.Option(this, value)
            arguments
                this
                value   (1,1)   EBKernelOptions
            end

            if this.IsRunning
                throw(MException("EBKernel:invalidAccess", ...
                        "Running kernel option is unsetable"));
            else
                this.options = value;
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
            if this.devices.isConfigured && isKey(this.devices, "daq_device")
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

        %% Video Getter
        function value = get.Video(this)
            value = this.videos;
        end
    end

    methods(Access = ?EasyBehaviour)
        function add_device(this, dev)
            arguments
                this
                dev     (1,1)   dictionary
            end

            if this.IsRunning
                throw(MException("EBKernel:invalidAccess", ...
                        "EBKernel does not support hot swap."));
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

        function update_paradigm(this, pdgm)
            arguments
                this
                pdgm     (1,1)   EBParadigm
            end

            if this.IsRunning
                throw(MException("EBKernel:invalidAccess", ...
                    "EBKernel does not support hot modifying."));
            else
                % replace experiment
                this.paradigm = pdgm;
            end
        end

        % run with kernal options
        function run(this)
            %% Configure analysis tools
            this.tracker = Tracker(this.options.TrackerOptions);
            this.parameterizer = Parameterizer(this.options.ParameterizerOptions);
            this.pfanalyzer = PopulationAnalyzer(this.options.PopulationOptions);

            %% Enable hardware process

            % turn on DAQ device (first of all)
            this.devices{"daq_device"}.Run();   % waitfor camera switching

            % turn on camera and acquire right now
            this.devices{"camera"}.Acquire(this.duration + this.DAQ_DELAY);
            pause(this.DAQ_DELAY);  % waitfor DAQ synchronous
            
            % start time align to camera
            this.start_time = this.devices{"camera"}.StartTime;

            %% Start calculation (backend parallel in each sub function)
            scale = this.options.ScaleOptions;
            boxes_tot = {double.empty(0, 6), double.empty(0, 6)};
            gcs_tot = {};
            while this.devices{"camera"}.IsRunning
                % require current frame
                frame = this.devices{"camera"}.GetCurrentFrame();
                % require current task
                task = this.devices{"daq_device"}.GetCurrentTask();
                if isempty(task), code = ""; else, code = task.code; end

                if this.feature(1) == EBStatus.TRACKER_ENABLE
                    % track followed, parallel
                    [boxes, gcs] = this.tracker.Track(boxes_tot{end-1}, boxes_tot{end}, frame);
                    
                    % combine detect box 
                    boxes_tot = [boxes_tot, {boxes}]; %#ok<AGROW>
                    gcs_tot = [gcs_tot, {gcs}]; %#ok<AGROW>
                    
                    if this.feature(2) == EBStatus.PARAMETERIZER_ENABLE
                        % parameterize followed, parallel

                        if this.feature(3) == EBStatus.POPULATION_ENABLE
                            % populaton analysis followed, parallel

                        end
                    end
                else
                    % tracking disabled
                    boxes_tot = [boxes_tot, {double.empty(0, 6)}]; %#ok<AGROW>
                    gcs_tot = [gcs_tot, {double.empty(0, 3)}]; %#ok<AGROW>
                end

                % construct VideoFrame
                vf = EBVideoFrame(frame{1}, frame{2}, code, scale, ...
                    boxes_tot{end}, gcs_tot{end});

                % save video frames
                this.videos.AddFrame(vf);
            end

            %% Post process variables
            
            % free
            delete(this.tracker);
            delete(this.parameterizer);
            delete(this.pfanalyzer);
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

    methods(Access = private)

    end
end

