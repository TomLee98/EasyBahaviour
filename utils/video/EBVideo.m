classdef EBVideo
    %EBVIDEO This is video defination
    
    properties(Access = private, Hidden, NonCopyable)
        video_frames    (1,1)   mQueue
        frame_rate      (:,1)   double
        mode            (1,1)   string
    end
    
    methods
        function this = EBVideo(mode_, video_, frame_rate_)
            %EBVIDEO A Constructor
            arguments
                mode_           (1,1)   string  {mustBeMember(mode_, ["static", "dynamic"])} = "dynamic"
                video_          (:,:,:)         {mustBeNonnegative}  = []
                frame_rate_     (1,1)   double  {mustBePositive} = 25
            end

            % set mode
            this.mode = mode_;

            % initialize data
            switch mode_
                case "static"
                    if isempty(video_)
                        throw(MException("Video:invalidConstruction", ...
                            "Images can not be empty when instance generation."));
                    end
                case "dynamic"
                    %
                otherwise
            end

            if ~isempty(video_)
                % set timestamps
                if isempty(time_)
                    warning("Video:timeLost", "Timestamps lost, frame " + ...
                        "indices will replace it.");
                    this.time = (1:size(images_, 3))';
                else
                    if numel(time_) ~= size(images_, 3)
                        throw(MException("Video:invalidConstruction", ...
                            "Number of images and timestamps does not match."));
                    else
                        this.time = time_;
                    end
                end

                % set data
                this.image_queue = mQueue();
                for k = 1:size(images_, 3)
                    this.image_queue.enqueue(images_(:,:,k));
                end
            else
                if ~isempty(time_)
                    throw(MException("Video:invalidConstruction", ...
                        "Number of images and timestamps does not match."));
                else
                    this.image_queue = mQueue();
                    this.time = time_;
                end
            end
        end

        function delete(this)
            delete(this.video_frames);

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
                    throw(MException("Video:invalidUse", ...
                        "Static Video is read-only object."));
                case "dynamic"
                    this.video_frames.enqueue(frame_);
            end
        end

        function frame = GetLastFrame(this)
            n = numel(this.video_frames);
            if n > 0
                frame = GetFrame(this, n);
            else
                warning("Video:emptyVideo", "No valid frames.");
                frame = EBVideoFrame();
            end
        end

        function Clear(this)
            % clean up frames queue
            this.video_frames.clear();

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
                warning("Video:outOfBoundary", "Index out of video frames.");
                value = EBVideoFrame();
            else
                value = this.video_frames.get(fIndex);
            end
        end
    end

    methods (Static)
        function e = empty()
            e = EBVideo("dynamic", [], []);
        end
    end
end

