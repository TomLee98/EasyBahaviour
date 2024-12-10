classdef mQueueHD < matlab.mixin.Copyable
    %MQUEUEHD This class provide a basic queue and some operator where 
    % temporary data storage on hard drive, note that only array

    properties(GetAccess = public, Dependent)
        SourceFolder
        MaxMBytesRate
    end
    
    properties (Access = private)
        length
        max_mbytes_rate
    end

    properties (GetAccess = private, SetAccess = immutable)
        data_type
        source
    end

    properties(Access=private, Hidden, NonCopyable)
        hM          % matfile object
    end
    
    methods
        function this = mQueueHD(src_, dataType_, dataBytes, speedTest_)
            arguments
                src_        (1,1)   string      = ""
                dataType_   (1,1)   string  {mustBeMember(dataType_, ["numeric", "others"])} = "others"
                dataBytes   (1,1)   double  {mustBeNonNan} = inf
                speedTest_  (1,1)   logical     = true
            end

            %MQUEUE Initialize an empty queue
            this.length = 0;
            this.data_type = dataType_;
            
            % genearte test folder
            if isequal(src_, "")
                % create tmporary folder
                src_ = findTmpFolder(dataBytes);
            elseif isfolder(src_)
                % user specified, omit dataBytes
            else
                throw(MException("mQueueHD:invalidSourceFolder", ...
                    "Source must be an exist folder or ''"));
            end
            this.source = src_;

            % write speed test
            if speedTest_ == true
                this.max_mbytes_rate = mQueueHD.speedTest(src_, dataType_);
            else
                this.max_mbytes_rate = nan;
            end

            % create empty cell array to mat file
            new_file_name = mQueueHD.createEmptyBuffer(src_);

            % connect to mat file
            this.hM = matfile(new_file_name, "Writable",true);
        end

        function enqueue(this, d)
            % write to hM
            try
                this.hM.data_v(1,this.length+1) = {d};
                this.length = this.length + 1;
            catch ME
                rethrow(ME);
            end
        end

        function item = dequeue(this)
            if ~this.isempty()
                try
                    item = this.head();
                    this.hM.data_v(1,1) = [];
                    this.length = this.length - 1;
                catch ME
                    rethrow(ME);
                end
            else
                item = [];
            end
        end

        function item = head(this)
            if ~this.isempty()
                try
                    item = this.hM.data_v(1,1);
                    item = item{:};
                catch ME
                    rethrow(ME);
                end
            else
                item = [];
            end
        end

        function item = tail(this)
            if ~this.isempty()
                try
                    item = this.hM.data_v(1,end);
                    item = item{:};
                catch ME
                    rethrow(ME)
                end
            else
                item = [];
            end
        end

        function tf = isempty(this)
            tf = (this.length == 0);
        end

        function len = numel(this)
            len = this.length;
        end

        function clear(this)
            % remove file and create new buffer
            this.cleanup();

            fname = mQueueHD.createEmptyBuffer(this.source);

            % connect to new buffer
            this.hM = matfile(fname, "Writable",true);
        end

        function delete(this)
            % deconstructor
            this.cleanup();
        end

        function value = get.MaxMBytesRate(this)
            % This properties run speed test if needed
            if isnan(this.max_mbytes_rate)
                value = mQueueHD.speedTest();
                this.max_mbytes_rate = value;
            else
                value = this.max_mbytes_rate;
            end
        end

        function value = get.SourceFolder(this)
            value = this.source;
        end
    end

    methods(Access = public, Hidden)
        function value = get(this, index)
            arguments
                this
                index   (1, 1)  double  {mustBePositive, mustBeInteger}
            end
            
            if index <= this.length
                value = this.hM.data_v(1,index);
                value = value{:};
            else
                throw(MException("mQueue:OutOfBoundary", "Index out of array " + ...
                    "boundary."));
            end
        end
    end

    methods(Access = private, Hidden)
        function cleanup(this)
            % note that only 'inaccessible' handles stored if pushed, so 
            % that we ignore the memory security which handled by
            % MATLAB kernel

            file_ = this.hM.Properties.Source;

            delete(this.hM);    % disconnect matfile object (logical)

            this.hM = [];
            this.length = 0;

            % remove data from hard drive
            try
                delete(file_);
            catch ME
                rethrow(ME);
            end
        end
    end

    methods(Access = protected)
        function cpt = copyElement(this)
            cpt = copyElement@matlab.mixin.Copyable(this);

            % only one handle pointed to one file
            % create another file
            file_ = newRandFileName(this.source);

            try
                % copy file
                copyfile(this.hM.Properties.Source, file_);

                % connect to new file, inherit writable property
                cpt.hM = matfile(file_, "Writable",this.hM.Properties.Writable);
            catch ME
                rethrow(ME);
            end
        end
    end

    methods(Static, Hidden)
        function speed = speedTest(folder, dataType, chunkSize, times)
            % This function select driveLetter and test the basic data 
            % write speed (typical image size if chunkBytes Omitted)
            arguments
                folder      (1,1)   string  = ""
                dataType    (1,1)   string  {mustBeMember(dataType, ["numeric", "others"])} = "others"
                chunkSize   (1,2)   double  {mustBePositive, mustBeInteger} = [1024, 1024]
                times       (1,1)   double  {mustBePositive, mustBeInteger} = 25
            end

            if ~isfolder(folder)
                folder = findTmpFolder();
            end

            % new object
            queue_hd = mQueueHD(folder, dataType, inf, false);

            data = uint16(rand(chunkSize)*4095);

            % speed test
            tic;
            for n = 1:times
                queue_hd.enqueue(data);
            end
            t = toc;

            speed = (prod(chunkSize)*2*times/1024/1024)/t;
        end

        function fname = createEmptyBuffer(src_)
            arguments
                src_    (1,1)   string  {mustBeFolder}
            end

            fname = newRandFileName(src_);
            while isfile(fname)
                fname = newRandFileName(src_);
            end

            data_v = {};

            save(fname, "data_v", "-v7.3", "-nocompression");

            % modify file attribute as 'hidden' to prevent user's misoperation
            [status, ~] = fileattrib(fname, '+h +w', '');
            if ~status
                throw(MException("mQueueHD:invalidPermission", ...
                    "You have no file attributes permission."));
            end
        end
    end
end

