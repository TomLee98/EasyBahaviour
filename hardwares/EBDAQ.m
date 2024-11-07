classdef EBDAQ < handle
    %VALVES This is general EBvalves defination

    properties(Constant)
        NLINE_EACH_PORT = 8
    end

    properties(SetAccess=immutable, GetAccess=public)
        % Interpreter - Specifies the interpreter transform  VCSL code to
        % value control command
        % Read/Write Access - Read-only
        % Accepted Values - function_handle with <code, map> as input parameters
        % Default - vcsl
        Interpreter
    end
    
    properties(Access = private)
        adjust_time     (1,1)   double              % avoiding timer error accumulation, seconds
        cam_checker     (1,1)   timer               % agent for check camera port signal
        cam_vl_init     (1,1)   logical             % the initial camera votage level
        code_file       (1,1)   string              % source code file full path
        commands        (:,4)   table               % table for valve commands, [code, mixing, cmd, delay]
        cmd_pointer     (1,1)   double              % positive integer indicates command index
        cmd_sender      (1,1)   timer               % agent for sending command to hardware
        cport           (1,2)   double              % [port, line], indicate camera switch channel
        daqobj          (:,1)                       % DataAcquisition object, just control hardware
        device_id       (1,1)   string              % device identity
        duration        (:,1)   double              % time queue duration, timer check it every 10 ms
        port_n          (1,1)   double              % DAQ device port number
        start_t         (1,1)   uint64              % valves running start time, get by tic
        vport           (:,2)   double              % [port, line], indicate valves channel
        vport_mapping   (1,1)   dictionary          % the valves port mapping, <string> -> <cell>, indicate a transformation
        vendor          (1,1)   string              % device vendor
    end

    properties (Access=public, Dependent)
        CameraPort          % set/get, 1-by-2 double, nonnegtive integer
        CodeFile            % set/get, 1-by-1 string
        DeviceID            % set/get, 1-by-1 string
        Duration            % ___/get, n-by-1 double
        IsCommandReady      % ___/get, 1-by-1 logical
        IsConnected         % ___/get, 1-by-1 logical
        IsRunning           % ___/get, 1-by-1 logical
        PortNumber          % set/get, 1-by-1 double, positive integer
        TaskTable           % ___/get, n-by-2 table
        ValvesPort          % set/get, n-by-2 double, nonnegtive integer
        ValvesPortMapping   % ___/get, 1-by-1 dictionary
        Vendor              % set/get, 1-by-1 string
    end
    
    methods
        function this = EBDAQ(itp_)
            %VALVES A constructor
            arguments
                itp_            (1,1)   function_handle     = @vcsl
            end

            % init immutable variables
            this.Interpreter = itp_;

            % 
            this.adjust_time = 0;
            this.cam_vl_init = false;
            this.code_file = string(['.', filesep, 'exdef', filesep, 'valve.vcs']);
            this.commands = table('Size', [0, 4], ...
                                  'VariableTypes',{'string', 'cell',   'double', 'double'}, ...
                                  'VariableNames',{'code',   'mixing', 'cmd',    'delay'});
            this.cmd_pointer = 0;
            this.cport = [nan, nan];
            this.daqobj = [];
            this.device_id = "";
            this.duration = [];
            this.port_n = nan;
            this.start_t = 0;
            this.vport = [nan, nan];
            this.vport_mapping = dictionary([], []);
            this.vendor = "";

            % init command sending timer
            this.cmd_sender = timer("BusyMode",         "error", ...
                                    "ExecutionMode",    "fixedRate", ...
                                    "Name",             "EBValves_Agent", ...
                                    "Period",           0.025, ...           % 0.02s is minimal period
                                    "TasksToExecute",   inf, ...
                                    "TimerFcn",         @this.send_one_command, ...
                                    "StartFcn",         @this.send_reset);

            % init camera port checking timer
            this.cam_checker = timer("BusyMode",        "drop", ...
                                     "ExecutionMode",   "fixedDelay", ...
                                     "Name",            "EBCamera_Listener", ...
                                     "Period",          0.01, ...          % detection error
                                     "TasksToExecute",  inf, ...
                                     "TimerFcn",        @this.listen_for_trigger);

            % disable raw devices warning
            EBDAQ.ManageWarnings("off");
        end

        function delete(this)
            %
            stop(this.cam_checker);
            delete(this.cam_checker);

            % free data acquisition object
             if this.IsConnected
                % if running, stop
                if this.IsRunning, stop(this.cmd_sender); end

                % disconnect DAQ device
                this.Disconnect();
             end

            delete(this.cmd_sender);

            EBDAQ.ManageWarnings("on");

            % free memory
            clear("this");
        end

        %% CameraPort Getter & Setter
        function value = get.CameraPort(this)
            value = this.cport;
        end

        function set.CameraPort(this, value)
            arguments
                this
                value   (1,2)   double
            end

            if ~this.IsConnected
                if all(~isnan(value))
                    if (value(1) < this.port_n) ...
                            && (value(2) < this.NLINE_EACH_PORT)
                        this.cport = value;
                    else
                        throw(MException("EBDAQ:invalidParameter", ...
                            "<port>/<line> are out of range."));
                    end
                else
                    % keep [nan, nan]
                end
            else
                throw(MException("EBDAQ:invalidAccess", "Connected daq-device " + ...
                    "camera port is unsetable."))
            end
        end

        %% CodePath Getter & Setter
        function value = get.CodeFile(this)
            if ~isempty(this.code_file) ...
                    && isfile(this.code_file)
                value = this.code_file;
            else
                value = "";
                warning("EBValve:noCodeAssigned", "Code file has not been assigned.");
            end
        end

        function set.CodeFile(this, value)
            arguments
                this
                value   (1,1)  string   {mustBeFile}
            end

            if this.IsConnected
                if this.IsRunning
                    throw(MException("EBDAQ:invalidAccess", "Running daq-device " + ...
                        "code file is unsetable."));
                end
            end

            [~, ~, ext] = fileparts(value);

            if ~isequal(ext, ".vcs")
                throw(MException("EBValve:invalidCodeFile", "Unsupported " + ...
                    "VCSL code file."));
            else
                this.code_file = value;
            end
        end

        %% DeviceID Getter & Setter
        function value = get.DeviceID(this)
            value = this.device_id;
        end

        function set.DeviceID(this, value)
            arguments
                this 
                value   (1,1)   string 
            end

            if ~this.IsConnected
                this.device_id = value;
            else
                throw(MException("EBDAQ:invalidAccess", "Connected daq-device " + ...
                    "device ID is unsetable."));
            end
        end

        %% Duration Getter
        function value = get.Duration(this)
            value = this.duration;
        end

        %% IsCommandReady Getter
        function value = get.IsCommandReady(this)
            value = ~isempty(this.commands);
        end

        %% IsConnected Getter
        function value = get.IsConnected(this)
            value = (~isempty(this.daqobj) && isvalid(this.daqobj));
        end

        %% IsRunning Getter
        function value = get.IsRunning(this)
            if this.IsConnected
                % mark the agent running status
                value = isequal(this.cmd_sender.Running, "on");
            else
                throw(MException("EBDAQ:invalidAccess", "Disconnected daq-device " + ...
                    "can not get status."));
            end
        end

        %% PortNumber Getter & Setter
        function value = get.PortNumber(this)
            value = this.port_n;
        end

        function set.PortNumber(this, value)
            arguments
                this
                value   (1,1)   double  {mustBePositive, mustBeInteger}
            end

            if ~this.IsConnected
                this.port_n = value;
            else
                throw(MException("EBDAQ:invalidAccess", "Running daq-device " + ...
                    "port number is unsetable."));
            end
        end

        %% TaskTable Getter
        function value = get.TaskTable(this)
            if this.IsConnected
                value = this.commands(:,[1,2,4]);
            else
                value = table('Size',[0,3], 'VariableTypes', {'string', 'cell', 'double'}, ...
                    'VariableNames',{'code', 'mixing', 'delay'});
            end
        end

        %% PortMapping Getter & Setter
        function value = get.ValvesPortMapping(this)
            value = this.vport_mapping;
        end

        %% ValvesPort Getter & Setter
        function value = get.ValvesPort(this)
            value = this.vport;
        end

        function set.ValvesPort(this, value)
            arguments
                this
                value   (:,2)   double  {mustBeNonnegative, mustBeInteger}
            end

            if ~this.IsConnected
                if all(value(1) < this.port_n) ...
                        && all(value(2) < this.NLINE_EACH_PORT)
                    this.vport = value;
                else
                    throw(MException("EBDAQ:invalidParameter", ...
                        "<port>/<line> are out of range."));
                end
            else
                throw(MException("EBDAQ:invalidAccess", "Connected daq-device " + ...
                    "valves port is unsetable."))
            end
        end

        %% Vendor Getter & Setter
        function value = get.Vendor(this)
            value = this.vendor;
        end

        function set.Vendor(this, value)
            arguments
                this
                value   (1,1)   string  {mustBeMember(value, ...
                                        ["ni","adi","mcc","directsound","digilent"])}
            end

            if ~this.IsConnected
                this.vendor = value;
            else
                throw(MException("EBDAQ:invalidAccess", "Connected daq-device " + ...
                    "vendor is unsetable."));
            end
        end

    end

    methods(Access = public)
        function Connect(this)
            if ~this.IsConnected
                try
                    % connect daq device
                    this.daqobj = daq(this.Vendor);

                    % configure line property
                    % camera channel as input:
                    camera_channel = sprintf("port%d/line%d", this.cport);
                    addinput(this.daqobj, this.device_id, camera_channel, "Digital");

                    % record initial camera port votage level
                    [this.cam_vl_init, ~, ~] = read(this.daqobj, OutputFormat="Matrix");

                    % valves channel as output:
                    for k = 1:size(this.vport, 1)
                        valve_channel = sprintf("port%d/line%d", this.vport(k,:));
                        addoutput(this.daqobj, this.device_id, valve_channel, "Digital");
                    end

                    % interpret code file
                    this.interpret();
                catch ME
                    throw(ME);
                end
            else
                warning("EBDAQ:connectedInstance", "An EBDAQ instance is already " + ...
                    "connected. You can create other EBDAQ for multi-switching.");
            end
            
        end

        function Disconnect(this)
            if this.IsConnected
                % delete video control obejct
                delete(this.daqobj); 
                this.daqobj = [];

                % reset command pointer
                this.cmd_pointer = 0;
            end
        end

        function MakeValvePortMapping(this, valves)
            arguments
                this
                valves     (:,1)   string
            end

            if numel(valves) ~= size(this.vport, 1)
                throw(MException("EBDAQ:invalidKeys", "The number of valves " + ...
                    "and wiring ports does not match."));
            else
                % clear vport_mapping
                this.vport_mapping = dictionary();

                % construct simple one-to-one mapping
                maps = eye(numel(valves), numel(valves));
                for k = 1:numel(valves)
                    this.vport_mapping(valves(k)) = {maps(k,:)};
                end

                % add "CLOSE"
                this.vport_mapping("CLOSE") = {zeros(1,numel(valves))};
            end
        end

        function Test(this)
            % generate temporary test command
            this.commands = [array2table(strings(size(this.vport,1)+1,1), "VariableNames",{'code'}), ...
                             cell(size(this.vport,1)+1,1), ...
                             cell2table([this.vport_mapping.values, ...
                             repmat({2}, size(this.vport,1)+1, 1)], "VariableNames",{'cmd', 'delay'})];
            
            % configure duration
            this.duration = [0;2;4;6;8;10];

            % trigger sender
            start(this.cmd_sender);
        end

        function Run(this)
            % EBDAQ running before any other EBDevice
            % EBCamera trigger the inner cmd_sender timer

            % interpret for last update
            this.interpret();

            start(this.cam_checker);    
        end

        function value = GetCurrentValves(this)
            if this.IsConnected
                if this.cmd_pointer > 0
                    value = this.commands.cmd(this.cmd_pointer, :);
                else
                    value = [];
                end
            else
                throw(MException("EBDAQ:invalidAccess", "DAQ Controller is " + ...
                    "not running."));
            end
        end

        function Abort(this)
            % stop sending
            stop(this.cmd_sender);

            % give up counter
            this.cmd_pointer = 0;
        end

        function Stop(this)
            % stop sending only
            stop(this.cmd_sender);
        end
    end

    methods (Access = private)
        function interpret(this)
            % EBKernel call this
            try
                this.commands = this.Interpreter(this.code_file, ...
                                                 this.vport_mapping);
                this.duration = [0; cumsum(max(this.commands.delay, 0.05))];
            catch ME
                throwAsCaller(ME);
            end
        end

        function send_one_command(this, src, evt)
            src; %#ok<VUNUS>
            evt; %#ok<VUNUS>

            rt = toc(this.start_t);

            if rt >= this.duration(this.cmd_pointer + 1)
                this.cmd_pointer = this.cmd_pointer + 1;

                % send one command
                write(this.daqobj, this.commands.cmd(this.cmd_pointer, :));
            end
        end

        function send_reset(this, src, evt)
            src; %#ok<VUNUS>
            evt; %#ok<VUNUS>

            this.cmd_pointer = 0;
            this.start_t = tic;     % record start time
        end

        function listen_for_trigger(this, src, evt)
            src; %#ok<VUNUS>
            evt; %#ok<VUNUS>

            [cam_vl, ~, ~] = read(this.daqobj, OutputFormat="Matrix");
            if cam_vl ~= this.cam_vl_init       % detected voltage changing
                stop(src);      % stop this timer immediately

                % trigger valves running
                start(this.cmd_sender);
            end
        end
    end

    methods (Static)
        function ManageWarnings(state)
            arguments
                state    (1,1)   string  {mustBeMember(state, ["on","off"])} = "off"
            end

           warning(state, 'daq:Session:onDemandOnlyChannelsAdded');
        end
    end
end
