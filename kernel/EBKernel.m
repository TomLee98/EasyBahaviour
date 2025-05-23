classdef EBKernel < handle
    %EBKERNEL This class defines an EBKernel object, which accept <devices>
    % and <experiment>, and it will control <devices> under <experiment>
    % workflow
    % Note that kernel only provides the basic properties and function for
    % better performance
    % EBKernel manage two data queue: raw data()

    properties (Constant, Hidden)
        DAQ_DELAY = 0.3             % DAQ-Kernel response delay (to camera) 
    end

    properties(Access = public, Dependent)
        CurrentVideoFrame   % ___/get, 1-by-1 VideoFrame object
        Devices             % ___/get, 1-by-1 dictionary
        Feature             % set/get, 1-by-3 EBStatus array, [TrackerStatus, ParameterizerStatus, PopulationStatus]
        Images              % ___/get, 1-by-1 Images object
        ImagesInfo          % ___/get, 0-by-13 or 1-by-13 table
        IsRunning           % ___/get, 1-by-1 logical, indicate if kernel is running
        LeftTime            % ___/get, 1-by-1 double, left time before stop recording, seconds
        NFramesProcessed    % ___/get, 1-by-1 processed frames with features
        Option              % set/get, 1-by-1 EBKernelOption, the options for running feature
        ParadigmFeatures    % ___/get, 1-by-k table as metadata for offline analyzer "MAGAT"(Marc, et al., N.M, 2012.)
        Status              % ___/get, 1-by-3 EBStatus array, with [DeviceStatus, KernelStatus, TaskStatus]
        Tasks               % ___/get, n-by-2 table, with 
        TotalTime           % ___/get, 1-by-1 double, total experiment time, seconds
        Video               % ___/get, 1-by-1 EBVideo object
    end
    
    properties(Access = private)
        body            (1,1)                                           % container/caller, who ask kernel for update info
        devices         (1,1)   dictionary          = dictionary()      % devices dictionary
        duration        (1,1)   double              = 0                 % task duration
        feature         (1,3)   EBStatus                                % task feature, function configuration
        options         (1,1)   EBKernelOptions                         % task options
        paradigm        (1,1)   EBParadigm                              % EBParadigm object, experiment pipeline defination
        parameterizer   (1,1)   Parameterizer                           % Parameterizer object, motion parameterize
        npcs_frames     (1,1)   double              = 0                 % Processed frames number with feature
        pfanalyzer      (1,1)   PopulationAnalyzer                      % PopulationAnalyzer object, analyze population features
        results         (1,1)   struct                                  % store acquired results defined by feature
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
                    if isobject(this.devices{ky}) && isvalid(this.devices{ky})
                        this.devices{ky}.delete();       % call object delete
                    end
                end
            end

            % paradigm clean
            % ~


            % variables clean up
            this.videos.delete();
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
        function value = get.Images(this)
            if this.devices.isConfigured ...
                    && this.devices{"camera"}.IsConnected
                value = this.devices{"camera"}.ImagesBuffer;    % just read buffer
            else
                value = EBImages.empty();
            end
        end

        %% FramesInfo Getter
        function value = get.ImagesInfo(this)
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
                value.xResolution = this.options.ScaleOptions.XRes;
                value.yResolution = this.options.ScaleOptions.YRes;
                value.frameRate = this.devices{"camera"}.AcquireFrameRate;
                value.bitDepth = this.devices{"camera"}.BitDepth;

                value.deviceModel = this.devices{"camera"}.DeviceModelName;
                value.resolutionUnit = this.options.ScaleOptions.ResUnit;
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

        function value = get.NFramesProcessed(this)
            value = this.npcs_frames;
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

        %% ParadigmFeatures Getter
        function value = get.ParadigmFeatures(this)
            if this.Status(3) == EBStatus.TASK_DONE
                BinX = this.devices{"camera"}.BinningHorizontal;
                BinY = this.devices{"camera"}.BinningVertical;
                if BinX ~= BinY
                    warning("EBKernel:notSquaredPixel", "Binning pixel is not squared, " + ...
                        "modified as maximum binning.");
                    BinX = max(BinX, BinY);
                end
                Mightex_Bin = BinX;
                Mightex_CameraID = this.devices{"camera"}.DeviceID;
                Mightex_Column = this.devices{"camera"}.ROIWidth;
                Mightex_Row = this.devices{"camera"}.ROIHeight;
                Mightex_ExposureTime = this.devices{"camera"}.ExposureTime/1000; % to ms
                Mightex_FrameRate = this.devices{"camera"}.AcquireFrameRate;    % different from recording but useful
                Mightex_XStart = this.devices{"camera"}.OffsetX;
                Mightex_YStart = this.devices{"camera"}.OffsetY;
                Mightex_ProcessFrameType = 0;       % NULL
                Mightex_FilterAcceptForFile = 1;    % DEFAULT
                Mightex_BlueGain = 1;               % DEFAULT
                Mightex_RedGain = 1;                % DEFAULT
                Mightex_TriggerOccurred = 0;        % NULL
                Mightex_TriggerEventCount = 0;      % NULL
                value = table(Mightex_Bin, Mightex_CameraID,...
                    Mightex_Column, Mightex_Row, Mightex_ExposureTime, ...
                    Mightex_FrameRate, Mightex_XStart, Mightex_YStart, ...
                    Mightex_ProcessFrameType, Mightex_FilterAcceptForFile, ...
                    Mightex_BlueGain, Mightex_RedGain, Mightex_TriggerOccurred, ...
                    Mightex_TriggerEventCount);
            else
                % initialized empty table
                value = table('Size', [0, 14], ...
                    'VariableTypes',repmat({'double'},1,14), ...
                    'VariableNames',{'Mightex_Bin', 'Mightex_CameraID',...
                    'Mightex_Column', 'Mightex_Row', 'Mightex_ExposureTime', ...
                    'Mightex_FrameRate', 'Mightex_XStart', 'Mightex_YStart', ...
                    'Mightex_ProcessFrameType', 'Mightex_FilterAcceptForFile', ...
                    'Mightex_BlueGain', 'Mightex_RedGain', 'Mightex_TriggerOccurred', ...
                    'Mightex_TriggerEventCount'});
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

        function clear_buffer(this)
            % clear video buffer
            this.videos.Clear();

            % clear camera buffer
            if this.devices.isConfigured && this.devices.isKey("camera")
                this.devices{"camera"}.Clear();
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
            this.npcs_frames = 0;

            %% Configure analysis tools
            this.tracker = Tracker(this.options.TrackerOptions);
            this.parameterizer = Parameterizer(this.options.ParameterizerOptions);
            this.pfanalyzer = PopulationAnalyzer(this.options.PopulationOptions);

            %% Enable hardware process

            % turn on DAQ device
            this.devices{"daq_device"}.Run();   % waitfor camera switching

            % turn on camera and acquire right now
            this.devices{"camera"}.Acquire(this.duration + this.DAQ_DELAY);
            pause(this.DAQ_DELAY);  % waitfor DAQ synchronous
            
            % start time align to camera
            this.start_time = this.devices{"camera"}.StartTime;

            %% Start calculation (backend parallel in each sub function)
            scale = this.options.ScaleOptions;

            while this.devices{"camera"}.IsRunning
                % require current frame
                frame = this.devices{"camera"}.GetCurrentFrame();

                % require current task
                task = this.devices{"daq_device"}.GetCurrentTask();
                if isempty(task), code = "CLOSE"; else, code = task.code; end

                if this.feature(1) == EBStatus.TRACKER_ENABLE
                    % track followed, parallel
                    boxes = this.tracker.track(frame);
                    
                    if this.feature(2) == EBStatus.PARAMETERIZER_ENABLE
                        % parameterize followed, parallel
                        boxess = {boxes};
                        params = this.parameterizer.gather(frame, boxess, "cp");
                        gcs = params.cp;

                        if this.feature(3) == EBStatus.POPULATION_ENABLE
                            % populaton analysis followed, parallel
                            this.pfanalyzer.extendTrace(gcs);
                            traces = this.pfanalyzer.Traces;
                        end
                    end
                    
                    pause(0.2); % wait for video player (parallel pool blocks other callback)
                else
                    boxes = Tracker.noneTrack();
                    traces = PopulationAnalyzer.noneTrace();

                    pause(2/this.devices{"camera"}.AcquireFrameRate);
                end

                % construct VideoFrame
                vf = EBVideoFrame(frame{1}, frame{2}, this.npcs_frames + 1, ...
                    code, scale, boxes, traces);

                % save video frames
                this.videos.AddFrame(vf);

                this.npcs_frames = this.npcs_frames + 1;
            end

            %% Post process variables

            % modify video frame rate
            frame_last = this.videos.GetLastFrame();
            this.videos.FrameRate = this.videos.FramesNum / frame_last.TimeStamp;
            
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

