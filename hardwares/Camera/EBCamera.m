classdef EBCamera < handle
    %CAMERA This class is camera defination for Easy Behaviour control
    %system, Which support basic camera settings and capturing images
    
    properties(Access=private)
        adapter     (1,1)   string                              % 1-by-1 string, the hardware adapter
        cap_agent   (1,1)   timer                               % 1-by-1 timer object
        devide_id   (1,1)   double                              % 1-by-1 double, positive integer
        duration    (1,1)   double                              % 1-by-1 double, indicate total acquire time
        fr_target   (1,1)   double      {mustBePositive} = 25   % 1-by-1 target frame rate, Hz
        iformat     (1,1)   string                              % 1-by-1 string, video format as "Mono8", "Mono12", etc
        start_t     (1,1)   uint64                              % 1-by-1 absolute acquire time, given by tic
        start_d     (1,1)   datetime                            % 1-by-1 datetime object, record absolute time
        viobj       (:,1)                                = []   % 1-by-1 videoinput object
        vsobj       (:,1)                                = []   % 1-by-1 videosource object
    end

    properties (Access=public)
        ROIAutoScale    (1,1)   logical  = true    % 1-by-1 logical, true as default
    end

    properties (SetAccess=private, GetAccess=public)
        ImagesBuffer     (1,1)   EBImages   % handle, not deep copy
    end

    properties (Access=public, Dependent)
        AcquireFrameRate        % set/get, 1-by-1 double positive, in [1, 100], 25 as default
        Adapter                 % set/get, 1-by-1 string, in ["gentl", "winvideo", "ni"]
        BinningHorizontal       % set/get, 1-by-1 double positive integer in [1,2,3,4]
        BinningVertical         % set/get, 1-by-1 double positive integer in [1,2,3,4]
        BitDepth                % ___/get, 1-by-1 double positive integer in [8,12]
        DateTime                % ___/get, 1-by-1 datetime object, captured absolute time
        DeviceID                % set/get, 1-by-1 double positive integer
        DeviceModelName         % ___/get, 1-by-1 string
        ExposureTime            % set/get, 1-ny-1 double positive integer in [5000, 1000000], unit as us
        ImageFormat             % set/get, 1-by-1 string, usual as "Mono8", "Mono12", etc
        Gamma                   % set/get, 1-by-1 double positive in (0, 4)
        IsConnected             % ___/get, 1-by-1 logical, false as default
        IsLiving                % ___/get, 1-by-1 logical, indicate camera living status
        IsRunning               % ___/get, 1-by-1 logical, false as default
        IsSuspending            % ___/get, 1-by-1 logical, false as default
        LineInverter            % set/get, 1-by-1 logical, true as default
        LineMode                % ___/get, 1-by-1 string, in ["input", "output"]
        LineSelector            % set/get, 1-by-1 string, in ["Line1", ..., "Line4"], "Line2" as default
        LineSource              % set/get, 1-by-1 string, in ["ExposureActive", "FrameTriggerWait", "FrameBurstTriggerWait"]
        MaxAcquireFrameRate     % ___/get, 1-by-1 double positive
        MaxFrameRate            % ___/get, 1-by-1 double positive
        OffsetX                 % set/get, 1-by-1 double nonnegtive integer
        OffsetY                 % set/get, 1-by-1 double nonnegtive integer
        ReadoutTime             % ___/get, 1-by-1 double positive integer
        ROIWidth                % set/get, 1-by-1 double positive integer
        ROIHeight               % set/get, 1-by-1 double positive integer
        StartTime               % ___/get, 1-by-1 uint64, exact absolute camera beginning time, come from tic
        VideoResolution         % ___/get, 1-by-2 double positive integer
    end

    methods
        function this = EBCamera(adapter_, identity_, format_)
            %EBCAMERA A constructor
            arguments
                adapter_     (1,1)   string  {mustBeMember(adapter_, ["winvideo", ...
                                             "gentl","ni"])} = "gentl"
                identity_    (1,1)   double  {mustBePositive, mustBeInteger} = 1
                format_      (1,1)   string  = "Mono12"
            end
            
            % set basic variables
            this.adapter = adapter_;
            this.devide_id = identity_;
            this.iformat = format_;

            % initialize video buffer
            this.ImagesBuffer = EBImages.empty();

            % initialize capture agent
            this.cap_agent = timer("Name",          "EBCamera_Agent", ...
                                   "BusyMode",      "drop", ...         % drop frame 
                                   "ExecutionMode", "fixedRate", ...
                                   "Period",        1/25,  ...          modified
                                   "TasksToExecute",inf, ...            modified
                                   "StartDelay",    0.25, ...
                                   "StartFcn",      @this.capture_begin, ...
                                   "StopFcn",       @this.capture_end, ...
                                   "TimerFcn",      @this.capture_one_frame);

            % disable raw devices warning
            EBCamera.ManageWarnings("off");
        end

        function delete(this)
            % remove capture agent timer
            if this.IsConnected
                % if running, stop
                if this.IsRunning, stop(this.cap_agent); end

                % disconnect camera
                this.Disconnect();
            end
            delete(this.cap_agent);

            % clear buffer
            delete(this.ImagesBuffer);

            EBCamera.ManageWarnings("on");

            % free memory
            clear("this");
        end

        %% AcquireFrameRate Getter & Setter
        function value = get.AcquireFrameRate(this)
            if this.IsConnected
                if ~this.IsRunning
                    value = this.fr_target;
                else
                    if this.ImagesBuffer.IsEmpty
                        % there is no frame in the queue
                        value = this.fr_target;     % replace by target frame rate
                    elseif this.ImagesBuffer.Size == 1
                        frame = this.ImagesBuffer.GetLastFrame();    % {image, time}
                        value = 1/frame{2};
                    else
                        n = this.ImagesBuffer.Size;
                        frame_last = this.ImagesBuffer.GetFrame(n);
                        frame_prev = this.ImagesBuffer.GetFrame(n-1);
                        value = 1/(frame_last{2} - frame_prev{2});
                    end
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        function set.AcquireFrameRate(this, value)
            arguments
                this
                value   (1,1)   double  {mustBePositive, mustBeInRange(value, 1, 100)}
            end
            if this.IsConnected
                if this.IsRunning
                    throw(MException("EBCamera:invalidAccess", "Running camera " + ...
                        "frame rate is unsetable."))
                else
                    this.fr_target = value;
                    this.cap_agent.Period = 1/value;    % unit as seconds
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% Adapter Getter & Setter
        function value = get.Adapter(this)
            value = this.adapter;
        end

        function set.Adapter(this, value)
            arguments
                this 
                value (1,1) string  {mustBeMember(value, ["winvideo","gentl","ni"])}
            end

            if ~this.IsConnected
                this.adapter = value;
            else
                throw(MException("EBCamera:invalidAccess", "Connected camera " + ...
                    "adapter is unsetable."));
            end
        end

        %% BinningHorizontal Getter & Setter
        function value = get.BinningHorizontal(this)
            if this.IsConnected
                value = this.vsobj.BinningHorizontal;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end
        
        function set.BinningHorizontal(this, value)
            arguments
                this
                value   (1,1)   {mustBeInRange(value, 1, 4), mustBeInteger}
            end

            if this.IsConnected
                if isrunning(this.viobj)|| this.IsLiving
                    throw(MException("EBCamera:invalidAccess", "Running camera " + ...
                        "binning is unsetable."));
                else
                    pre_value = this.vsobj.BinningHorizontal;
                    this.vsobj.BinningHorizontal = value;

                    if this.ROIAutoScale == true
                        this.OffsetX = round(this.OffsetX * pre_value/value);
                        this.ROIWidth = round(this.ROIWidth * pre_value/value);
                    else
                        rpos = this.VideoResolution;
                        if this.OffsetX + this.ROIWidth > rpos(3)
                            % reset ROI area on X
                            this.OffsetX = 0;
                            this.ROIWidth = rpos(3);
                        end
                    end
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% BinningVertical Getter & Setter
        function value = get.BinningVertical(this)
            if this.IsConnected
                value = this.vsobj.BinningVertical;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.BinningVertical(this, value)
            arguments
                this
                value   (1,1)   {mustBeInRange(value, 1, 4), mustBeInteger}
            end

            if this.IsConnected
                if isrunning(this.viobj) || this.IsLiving
                    throw(MException("EBCamera:invalidAccess", "Running camera " + ...
                        "binning is unsetable."));
                else
                    pre_value = this.vsobj.BinningVertical;
                    this.vsobj.BinningVertical = value;

                    if this.ROIAutoScale == true
                        this.OffsetY = round(this.OffsetY * pre_value/value);
                        this.ROIHeight = round(this.ROIHeight * pre_value/value);
                    else
                        rpos = this.VideoResolution;
                        if this.OffsetY + this.ROIHeight > rpos(4)
                            % reset ROI area on Y
                            this.OffsetY = 0;
                            this.ROIHeight = rpos(4);
                        end
                    end
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% BitDepth Getter
        function value = get.BitDepth(this)
            switch this.Adapter
                case "gentl"
                    switch this.ImageFormat
                        case "Mono8"
                            value = 8;
                        case "Mono12"
                            value = 12;
                        otherwise
                            throw(MException("EBCamera:invalidFormat", ...
                                "Only 'Mono8' and 'Mono12' are supported."));
                    end
                case "winvideo"
                    value = 8;  % test
                case "ni"
                    value = 8;
                otherwise
                    %
                    value = 8;
            end
        end

        %% DateTime Getter
        function value = get.DateTime(this)
            value = this.start_d;
        end

        %% DeviceID Getter & Setter
        function value = get.DeviceID(this)
            value = this.devide_id;
        end

        function set.DeviceID(this, value)
            arguments
                this 
                value (1,1) double  {mustBePositive, mustBeInteger}
            end

            if ~this.IsConnected
                this.devide_id = value;
            else
                throw(MException("EBCamera:invalidAccess", "Connected camera " + ...
                    "device identity is unsetable."));
            end
        end

        %% DeviceModelName Getter
        function value = get.DeviceModelName(this)
            if this.IsConnected
                value = this.vsobj.DeviceModelName;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        %% ExposureTime Getter & Setter
        function value = get.ExposureTime(this)
            if this.IsConnected
                value = this.vsobj.ExposureTime;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.ExposureTime(this, value)
            arguments
                this
                value   (1,1)   double  {mustBeInteger, mustBeInRange(value, 5000, 1000000)}
            end

            if this.IsConnected
                this.vsobj.ExposureTime = value;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% Format Getter && Setter
        function value = get.ImageFormat(this)
            value = this.iformat;
        end

        function set.ImageFormat(this, value)
            arguments
                this 
                value (1,1) string
            end

            if ~this.IsConnected
                this.iformat = value;
            else
                throw(MException("EBCamera:invalidAccess", "Connected camera " + ...
                    "format is unsetable."));
            end
        end

        %% Gamma Getter && Setter
        function value = get.Gamma(this)
            if this.IsConnected
                value = this.vsobj.Gamma;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.Gamma(this, value)
            arguments
                this
                value   (1,1)   double  {mustBeInRange(value, 0, 4)}
            end

            if this.IsConnected
                this.vsobj.Gamma = value;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% IsConnected Getter
        function value = get.IsConnected(this)
            value = (~isempty(this.viobj) && isvalid(this.viobj));
        end

        %% IsLiving Getter
        function value = get.IsLiving(this)
            if this.IsConnected
                value = isequal(this.viobj.Previewing, "on");
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get status."));
            end
        end

        %% IsRunning Getter
        function value = get.IsRunning(this)
            if this.IsConnected
                % mark the agent running status
                value = logical(this.start_t);
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get status."));
            end
        end

        function value = get.IsSuspending(this)
            value = false;
        end

        %% LineInverter Getter & Setter
        function value = get.LineInverter(this)
            if this.IsConnected
                value = isequal(this.vsobj.LineInverter, "True");
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.LineInverter(this, value)
            arguments
                this
                value   (1,1)   logical
            end

            if this.IsConnected
                if value
                    this.vsobj.LineInverter = "True";
                else
                    this.vsobj.LineInverter = "False";
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% LineMode Getter
        function value = get.LineMode(this)
            if this.IsConnected
                value = this.vsobj.LineMode;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        %% LineSelector Getter
        function value = get.LineSelector(this)
            if this.IsConnected
                value = this.vsobj.LineSelector;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.LineSelector(this, value)
            arguments
                this
                value   (1,1)   string  {mustBeMember(value, ["Line1", "Line2", ...
                                                              "Line3", "Line4"])}
            end

            if this.IsConnected
                this.vsobj.LineSelector = value;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% LineSource Getter & Setter
        function value = get.LineSource(this)
            if this.IsConnected
                value = this.vsobj.LineSource;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.LineSource(this, value)
            arguments
                this
                value   (1,1)   string  {mustBeMember(value, ["ExposureActive", ...
                                                              "FrameTriggerWait", ...
                                                              "FrameBurstTriggerWait"])}
            end

            if this.IsConnected
                this.vsobj.LineSource = value;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% MaxAcquireFrameRate Getter
        function value = get.MaxAcquireFrameRate(this)
            if this.IsConnected
                value = (3-sqrt(5))/2 * this.MaxFrameRate;  % 0.618 as experimental value
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        %% MaxFrameRate Getter
        function value = get.MaxFrameRate(this)
            if this.IsConnected
                value = 1e6/this.vsobj.SensorReadoutTime;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        %% OffsetX Getter & Setter
        function value = get.OffsetX(this)
            if this.IsConnected
                rpos = this.viobj.ROIPosition;
                value = rpos(1);
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.OffsetX(this, value)
            arguments
                this
                value   (1,1)   double  {mustBeNonnegative, mustBeInteger}
            end
            if this.IsConnected
                try
                    rpos = this.viobj.ROIPosition; rpos(1) = value;
                    this.viobj.ROIPosition= rpos;
                catch ME
                    throw(ME);
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% OffsetY Getter & Setter
        function value = get.OffsetY(this)
            if this.IsConnected
                rpos = this.viobj.ROIPosition;
                value = rpos(2);
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.OffsetY(this, value)
            arguments
                this
                value   (1,1)   double  {mustBeNonnegative, mustBeInteger}
            end
            if this.IsConnected
                try
                    rpos = this.viobj.ROIPosition; rpos(2) = value;
                    this.viobj.ROIPosition = rpos;
                catch ME
                    throw(ME);
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% ReadoutTime Getter
        function value = get.ReadoutTime(this)
            if this.IsConnected
                value = this.vsobj.SensorReadoutTime;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        %% ROIWidth Getter & Setter
        function value = get.ROIWidth(this)
            if this.IsConnected
                rpos = this.viobj.ROIPosition;
                value = rpos(3);
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.ROIWidth(this, value)
            arguments
                this
                value   (1,1)   double  {mustBePositive, mustBeInteger}
            end
            if this.IsConnected
                try
                    rpos = this.viobj.ROIPosition; rpos(3) = value;
                    this.viobj.ROIPosition = rpos;
                catch ME
                    throw(ME);
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% ROIHeight Getter & Setter
        function value = get.ROIHeight(this)
            if this.IsConnected
                rpos = this.viobj.ROIPosition;
                value = rpos(4);
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

        function set.ROIHeight(this, value)
            arguments
                this
                value   (1,1)   double  {mustBePositive, mustBeInteger}
            end
            if this.IsConnected
                try
                    rpos = this.viobj.ROIPosition; rpos(4) = value;
                    this.viobj.ROIPosition = rpos;
                catch ME
                    throw(ME);
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not set parameters."));
            end
        end

        %% StartTime Getter
        function value = get.StartTime(this)
            value = this.start_t;
        end

        %% VideoResolution Getter
        function value = get.VideoResolution(this)
            if this.IsConnected
                value = this.viobj.VideoResolution;
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get parameters."));
            end
        end

    end

    methods (Access = public)
        function Connect(this)
            if ~this.IsConnected
                try
                    % new object
                    this.viobj = videoinput(this.Adapter, ...
                                            this.DeviceID, ...
                                            this.ImageFormat);
                    this.vsobj = getselectedsource(this.viobj);

                    % set trigger parameters
                    triggerconfig(this.viobj, 'manual');
                    this.viobj.TriggerRepeat = inf;
                    this.viobj.FramesPerTrigger = 1;
                catch ME
                    throw(ME);
                end
            else
                warning("EBCamera:connectedInstance", "An EBCamera instance is already " + ...
                        "connected. You can create other EBCamera for multi-recording.");
            end
        end

        function Disconnect(this)
            if this.IsConnected
                % delete video control obejct
                delete(this.viobj); 
                this.viobj = [];
                this.vsobj = [];        % garbage collector auto clear

                % clear buffer (in memory)
                this.ImagesBuffer.Clear();
            end
        end

        function Live(this, state, hImage, fbd)
            % call inner function: preview
            arguments
                this
                state   (1,1)   string  {mustBeMember(state, ["on", "off"])} = "on"
                hImage  (1,:)                                                = []
                fbd     (1,1)   string  {mustBeMember(fbd, ["on", "off"])}   = "off"
            end

            if this.IsConnected
                switch state
                    case "on"
                        if this.IsLiving
                            warning("EBCamera:livingInstance", "An EBCamera " + ...
                                "instance is already living.");
                        else
                            this.viobj.PreviewFullBitDepth = fbd;

                            if isempty(hImage) || ~isvalid(hImage)
                                preview(this.viobj);
                            else
                                if isa(hImage, 'matlab.graphics.primitive.Image')
                                    preview(this.viobj, hImage);
                                else
                                    throw(MException("EBCamera:invalidArgument", ...
                                        "Unsupported image handle: hImage."));
                                end
                            end
                        end
                    case "off"
                        closepreview(this.viobj);
                    otherwise
                end
            else
                throw(MException("EBCamera:invalidAction", "Disconnected camera " + ...
                    "can not live."));
            end
        end

        function Acquire(this, time)
            arguments
                this
                time    (1,1)   double  {mustBePositive} = 10   % unit as seconds, 10 s as default
            end
            
            if this.IsConnected
                if this.IsRunning
                    warning("EBCamera:runningInstance", "An EBCamera instance is already " + ...
                        "running. You can create other EBCameras for multi-recording.");
                else
                    % set running duration
                    this.duration = time;

                    % clear buffer for initializing
                    this.ImagesBuffer.Clear();

                    % start timer
                    start(this.cap_agent);
                end
            else
                throw(MException("EBCamera:invalidAction", "Disconnected camera " + ...
                    "can not capture video."));
            end
            
        end

        function value = GetCurrentFrame(this)
            if this.IsConnected
                if this.IsRunning
                    [image, time] = this.ImagesBuffer.GetLastFrame();
                    value = {image, time};
                else
                    warning("EBCamera:invalidAccess", "No image is captured " + ...
                        "because EBCamera is not running.");
                    value = {[], []};
                end
            else
                throw(MException("EBCamera:invalidAccess", "Disconnected camera " + ...
                    "can not get images."));
            end
        end

        function Abort(this)
            % stop recording
            stop(this.cap_agent);

            % give up buffer
            this.ImagesBuffer.Clear();
        end

        function Stop(this)
            % stop recording only
            stop(this.cap_agent);
        end
    end

    methods (Access = private)
        function capture_one_frame(this, src, evt)
            src; %#ok<VUNUS>
            evt; %#ok<VUNUS>

            trigger(this.viobj);        % here is DAQ start time
            img = getdata(this.viobj);

            % input to images buffer
            timestamp = toc(this.start_t);
            if timestamp > this.duration
                % give up last frame
                stop(src);
            else
                this.ImagesBuffer.AddFrame(img, timestamp);
            end
        end

        function capture_begin(this, src, evt)
            src; %#ok<VUNUS>
            evt; %#ok<VUNUS>

            start(this.viobj);  % about 220 ms

            % set the camera beginning
            this.start_t = tic;
            this.start_d = datetime("now");
        end

        function capture_end(this, src, evt)
            src; %#ok<VUNUS>
            evt; %#ok<VUNUS>

            stop(this.viobj);
            this.start_t = 0;
        end
    end

    methods (Static)
        function ManageWarnings(state)
            arguments
                state    (1,1)   string  {mustBeMember(state, ["on","off"])} = "off"
            end

            warning(state, 'imaq:gige:adaptorPropertyHealed');
            warning(state, 'imaq:preview:typeBiggerThanUINT8');
        end
    end
end

