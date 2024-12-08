classdef EBVideoWriter < handle
    %VIDEOWRITER This class implement video writer
    
    properties(Access = private)
        video   (1,1)           % could be EBImages or EBVideo object 
        info    (1,1)   struct
    end
    
    methods
        function this = EBVideoWriter(source, options)
            %VIDEOWRITER A Constructor
            arguments
                source   (1,1)
                options (1,1)   struct
            end

            this.video = source;
            this.info = options;
        end
        
        function write(this)
            if this.video.IsEmpty
               warning("EBVideoWriter:noFramestoWrite", ...
                   "No frames could be written.");
               return;
            end

            [file, path] = uiputfile({'*.avi', 'Motion JPEG AVI(*.avi)'; ...
               '*.avi', 'Uncompressed Grayscale AVI (*.avi)'; ...
               '*.mp4',  'MPEG-4 (*.mp4)'; ...
               '*.mj2',  'Motion JPEG 2000 (*.mj2)'; ...
               '*.mj2',  'Uncompressed Motion MPEG 2000 (*.mj2)'}, ...
               "导出视频", "captured.avi");

            if ~isnumeric(file)
               file = fullfile(path, file);
               [~, ~, ext] = fileparts(file);

               switch ext
                   case ".tif"
                       this.saveAsTIFF(file);
                   case ".hdf5"
                       this.saveAsHDF5(file);
                   case ".mat"
                       this.saveAsMAT(file);
                   ot
                   otherwise
               end
            end
        end
    end
end

