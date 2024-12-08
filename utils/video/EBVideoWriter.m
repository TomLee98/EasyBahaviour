classdef EBVideoWriter < handle
    %VIDEOWRITER This class implement video writer

    properties(Access=public, Dependent)
        WrittingProgress        % ___/get, 1-by-1 nonnegtive double in (0, 1)
    end
    
    properties(Access = private)
        frame_fig   (1,1)   Figure
        info        (1,1)   struct
        matkers     (1,1)   struct
        prgs        (1,1)   double  = 0
        sblen       (1,1)   double
        video       (1,1)           % could be EBImages or EBVideo object 
    end
    
    methods
        function this = EBVideoWriter(source, options, markers, sbarlen)
            %VIDEOWRITER A Constructor
            arguments
                source      (1,1)
                options     (1,1)   struct
                markers     (1,1)   struct
                sbarlen     (1,1)   double  = 1
            end

            this.video = source;
            this.info = options;
            this.matkers = markers;
            this.sblen = sbarlen;
            
            this.frame_fig = figure("Name", "FrameGrabberWindow","Visible","off");
        end

        function value = get.WrittingProgress(this)
            value = this.prgs;
        end
        
        function delete(this)
            % ~
        end
    end

    methods (Access = public)
        function write(this)
            if this.video.IsEmpty
               warning("EBVideoWriter:noFramestoWrite", ...
                   "No frames could be written.");
               return;
            end

            switch this.info.OutputFormat
                case {'Motion JPEG 2000', 'Archival'}
                    [file, path, indx] = uiputfile({'*.mj2',  'Motion JPEG 2000 (*.mj2)'; ...
                        '*.mj2',  'Uncompressed Motion MPEG 2000 (*.mj2)'}, ...
                        "导出视频", "captured.mj2");
                case "MPEG-4"
                    [file, path] = uiputfile({'*.mp4',  'MPEG-4 (*.mp4)'}, ...
                        "导出视频", "captured.mp4");
                case {'Motion JPEG AVI', 'Grayscale AVI'}
                    [file, path, indx] = uiputfile({'*.avi', 'Motion JPEG AVI(*.avi)'; ...
                        '*.avi', 'Uncompressed Grayscale AVI (*.avi)'}, ...
                        "导出视频", "captured.avi");
                otherwise

            end

            if ~isnumeric(file)
               file = fullfile(path, file);
               [~, ~, ext] = fileparts(file);

               switch ext
                   case ".mp4"
                       saveAsMP4(this, file);
                   case ".avi"
                       saveAsAVI(this, file, indx);
                   case ".mj2"
                       saveAsMJ2(this, file, indx);
                   otherwise
               end
            end
        end
    end

    methods (Access = private)
        function saveAsMP4(this, file)
            vid = VideoWriter(file, "MPEG-4");
            vid.Quality = this.info.RenderingQuality;
            if isequal(class(this.video), "EBImages")
                if this.info.FrameRateSync == false
                    vid.FrameRate = this.info.OutputFrameRate;
                else
                    [~, t] = this.video.GetLastFrame();
                    vid.FrameRate = t/this.video.Size;
                end
                %% Export raw image
                open(vid);  % open file with fixed properties
                for fidx = 1:this.video.Size
                    [img, ~] = this.video.GetFrame(this, fidx);
                    writeVideo(vid, img);
                    this.prgs = fidx / this.video.Size;
                end
                close(vid);
                
            elseif isequal(class(this.video), "EBVideo")
                vid.FrameRate = this.video.FrameRate;

                %% Display Image on Figure
                frame = this.video.GetFrame(1); % get first frame: EBVideoFrame object

                hIm = imshow(zeros(size(frame.ImageData), "like", frame.ImageData), ...
                    "Parent", this.frame_fig);
                ax = this.frame_fig.CurrentAxes;
                spr = this.info.OutputFrameRate / this.video.FrameRate;

                initComponentsOn(ax);

                %% Export Image with markers
                open(vid);
                for fidx = 1:this.video.FramesNum
                    % display image
                    frame = GetFrame(this, fidx);
                    hIm.CData = frame.ImageData;

                    % update markers
                    updateComponentsOn(ax, frame, this.matkers, this.sblen, spr);

                    % grab frames and write
                    frame = getframe(this.frame_fig);

                    writeVideo(vid, frame);

                    this.prgs = fidx / this.video.Size;
                end
                close(vid);
            else
                throw(MException("EBVideoWriter:invalidSourceType", ...
                    "EBVideoWriter only support EBVideo or EBImages."));
            end
            
        end

        function saveAsAVI(this, file, type)

        end

        function saveAsMJ2(this, file, type)

        end
    end
end

