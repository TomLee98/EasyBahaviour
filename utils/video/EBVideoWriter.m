classdef EBVideoWriter < handle
    %VIDEOWRITER This class implement video writer

    properties(Access=public, Dependent)
        WrittingProgress        % ___/get, 1-by-1 nonnegtive double in (0, 1)
    end
    
    properties(Access = private)
        frame_fig   (1,1)
        info        (1,1)   struct
        markers     (1,1)   struct
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
            this.markers = markers;
            this.sblen = sbarlen;
            
            this.frame_fig = figure("Name", "FrameGrabber","Visible","off");
            axes(this.frame_fig);

            warning("off", 'MATLAB:audiovideo:VideoWriter:mp4FramePadded');
        end

        function value = get.WrittingProgress(this)
            value = this.prgs;
        end
        
        function delete(this)
            % ~
            if isvalid(this.frame_fig)
                close(this.frame_fig);
            end

            warning("on", 'MATLAB:audiovideo:VideoWriter:mp4FramePadded');
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
                case "Motion JPEG 2000"
                    [file, path] = uiputfile({'*.mj2',  'Motion JPEG 2000 (*.mj2)'}, ...
                        "导出视频", "captured.mj2");
                case "Archival"
                    [file, path] = uiputfile({'*.mj2',  'Uncompressed Motion MPEG 2000 (*.mj2)'}, ...
                        "导出视频", "captured.mj2");
                case "MPEG-4"
                    [file, path] = uiputfile({'*.mp4',  'MPEG-4 (*.mp4)'}, ...
                        "导出视频", "captured.mp4");
                case "Motion JPEG AVI"
                    [file, path] = uiputfile({'*.avi', 'Motion JPEG AVI(*.avi)'}, ...
                        "导出视频", "captured.avi");
                case "Grayscale AVI"
                    [file, path] = uiputfile({'*.avi', 'Uncompressed Grayscale AVI (*.avi)'}, ...
                        "导出视频", "captured.avi");
                case "Uncompressed AVI"
                    [file, path] = uiputfile({'*.avi', 'Uncompressed RGB AVI (*.avi)'}, ...
                        "导出视频", "captured.avi");
                otherwise
                    throw(MException("EBVideoWriter:invalidOutputFormat", ...
                        "Unsupported video format."));
            end

            if ~isnumeric(file)
               file = fullfile(path, file);
               [~, ~, ext] = fileparts(file);

               switch ext
                   case ".mp4"
                       saveAsMP4(this, file);
                   case ".avi"
                       saveAsAVI(this, file);
                   case ".mj2"
                       saveAsMJ2(this, file);
                   otherwise
               end
            end
        end
    end

    methods (Access = private)
        function saveAsMP4(this, file)
            vid = VideoWriter(file, "MPEG-4");
            vid.Quality = this.info.RenderingQuality;
            
            saveVideo(this, vid);
        end

        function saveAsAVI(this, file)
            switch this.info.OutputFormat
                case "Motion JPEG AVI"
                    % motion jpeg avi: compressed
                    vid = VideoWriter(file, "Motion JPEG AVI");
                    vid.Quality = this.info.RenderingQuality;
                case "Grayscale AVI"
                    % grayscale avi: uncompressed
                    vid = VideoWriter(file, "Grayscale AVI");
                case "Uncompressed AVI"
                    vid = VideoWriter(file, "Uncompressed AVI");
                otherwise
                    throw(MException("EBVideoWriter:invalidOutputFormat", ...
                        "Only Motion JPEG AVI and Grayscale AVI are supported."));
            end

            saveVideo(this, vid);
        end

        function saveAsMJ2(this, file)
            switch this.info.OutputFormat
                case "Motion JPEG 2000"
                    vid = VideoWriter(file, "Motion JPEG 2000");
                    vid.CompressionRatio = this.info.CompressionRatio;
                case "Archival"
                    vid = VideoWriter(file, "Archival");
                otherwise
                    throw(MException("EBVideoWriter:invalidOutputFormat", ...
                        "Only Motion JPEG AVI and Grayscale AVI are supported."));
            end

            saveVideo(this, vid);
        end

        function saveVideo(this, vid)
            if isequal(class(this.video), "EBImages")
                saveForEBImages(this, vid);
            elseif isequal(class(this.video), "EBVideo")
                saveForEBVideo(this, vid);
            else
                throw(MException("EBVideoWriter:invalidSourceType", ...
                    "EBVideoWriter only support EBVideo or EBImages."));
            end
        end

        function saveForEBImages(this, vid)
            if this.info.FrameRateSync == false
                vid.FrameRate = this.info.OutputFrameRate;
            else
                [~, t] = this.video.GetLastFrame();
                vid.FrameRate = this.video.Size/t;
            end

            gs_use = this.info.UseGrayscale;    % enable if RGB image is valid

            [img, ~] = this.video.GetLastFrame();
            output_size = [this.info.OutputHeight, this.info.OutputWidth];
            rs_use = any(output_size ~= size(img));

            %% Export raw image
            open(vid);  % open file with fixed properties
            for fidx = 1:this.video.Size
                [img, ~] = this.video.GetFrame(fidx);

                img = uint8(rescale(img, 0, 255));

                % change to RGB/uint8
                if ~gs_use, img = cat(3, img, img, img); end

                % resize
                if rs_use, img = imresize(img, output_size, this.info.Interpolation); end

                writeVideo(vid, img);

                this.prgs = fidx / this.video.Size;
            end
            close(vid);
        end

        function saveForEBVideo(this, vid)
            if this.info.FrameRateSync == true
                vid.FrameRate = this.video.FrameRate;
            else
                vid.FrameRate = this.info.OutputFrameRate;
            end

            gs_use = this.info.UseGrayscale;

            %% Display Image on Figure
            frame = this.video.GetFrame(1); % get first frame: EBVideoFrame object

            ax = this.frame_fig.CurrentAxes;
            hIm = imshow(zeros(size(frame.ImageData), "like", frame.ImageData), ...
                [0, 4096], "Parent", ax);

            spr = vid.FrameRate / this.video.FrameRate;

            initComponentsOn(ax, size(frame.ImageData, [2,1]));

            output_size = [this.info.OutputHeight, this.info.OutputWidth];
            rs_use = any(output_size ~= size(frame.ImageData));

            %% Export Image with markers
            open(vid);
            for fidx = 1:this.video.FramesNum
                % display image
                frame = this.video.GetFrame(fidx);
                hIm.CData = frame.ImageData;

                % update markers
                updateComponentsOn(ax, frame, this.markers, this.sblen, spr);

                % grab frames and write
                fframe = getframe(ax);

                if gs_use, fframe.cdata = rgb2gray(fframe.cdata); end

                if rs_use, fframe.cdata = imresize(fframe.cdata, output_size, this.info.Interpolation); end

                writeVideo(vid, fframe);

                this.prgs = fidx / this.video.FramesNum;
            end
            close(vid);
        end
    end
end
