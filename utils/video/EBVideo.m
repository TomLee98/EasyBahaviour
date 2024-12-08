classdef EBVideo < handle
    %EBVIDEO This is video defination

    properties(Access = public, Dependent)
        FramesNum
        FrameRate
        IsEmpty
        Mode
    end
    
    properties(Access = private, Hidden)
        video_frames    (1,1)   mQueue
        frame_rate      (:,1)   double
        mode            (1,1)   string
    end
    
    methods
        function this = EBVideo(mode_, frames_, frame_rate_)
            %EBVIDEO A Constructor
            arguments
                mode_           (1,1)   string  {mustBeMember(mode_, ["static", "dynamic"])}
                frames_         (:,1)   EBVideoFrame            = EBVideoFrame([], nan, nan)
                frame_rate_     (1,1)   double  {mustBePositive} = 25
            end

            % set variables
            this.mode = mode_;
            this.frame_rate = frame_rate_;
            this.video_frames = mQueue();

            % initialize data
            switch mode_
                case "static"
                    if isempty(frames_)
                        throw(MException("EBVideo:invalidConstruction", ...
                            "Images can not be empty when instance generation."));
                    end
                case "dynamic"
                    %
                otherwise
            end

            if ~isempty(frames_)
                for k = numel(frames_)
                    this.video_frames.enqueue(frames_(k));
                end
            end
        end

        function r = get.FramesNum(this)
            r = numel(this.video_frames);
        end

        function r = get.FrameRate(this)
            r = this.frame_rate;
        end

        function set.FrameRate(this, value)
            arguments
                this
                value   (1,1)   double  {mustBePositive}
            end

            this.frame_rate = value;
        end

        function r = get.IsEmpty(this)
            r = (numel(this.video_frames) == 0);
        end

        function r = get.Mode(this)
            r = this.mode;
        end

        function delete(this)
            this.video_frames.delete();

            clear("this");
        end
    end

    methods(Access = public)
        function AddFrame(this, frame_)
            arguments
                this
                frame_   (1,1)   EBVideoFrame
            end

            switch this.mode
                case "static"
                    throw(MException("EBVideo:invalidUse", ...
                        "Static EBVideo is read-only object."));
                case "dynamic"
                    this.video_frames.enqueue(frame_);
            end
        end

        function frame = GetLastFrame(this)
            n = numel(this.video_frames);
            if n > 0
                n = this.numel();
                frame = GetFrame(this, n);
            else
                warning("EBVideo:emptyVideo", "No valid frames.");
                frame = EBVideoFrame([], nan, nan);
            end
        end

        function Clear(this)
            % clean up frames queue
            this.video_frames.clear();
        end

        function value = numel(this)
            value = numel(this.video_frames);
        end
    end

    methods(Access=public, Hidden)
        function frame = GetFrame(this, fIndex)
            arguments
                this
                fIndex  (1,1)   double  {mustBePositive, mustBeInteger}
            end

            frame = this.get_frame_at(fIndex);
        end
    end

    methods(Access=private)
        function value = get_frame_at(this, fIndex)
            if fIndex > numel(this.video_frames)
                warning("EBVideo:outOfBoundary", "Index out of video frames.");
                value = EBVideoFrame([], nan, nan);
            else
                value = this.video_frames.get(fIndex);
            end
        end
    end

    methods (Static)
        function e = empty()
            e = EBVideo("dynamic");
        end
    end
end

