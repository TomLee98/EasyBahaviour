classdef ImageWriter < handle
    %IMAGEWRITER This is image writer class, which support write files as
    %defined format

    properties(SetAccess=immutable)
        dataset
        info
    end

    properties(Access=public, Dependent)
        WrittingProgress        % ___/get, 1-by-1 nonnegtive double in (0, 1)
    end

    properties(Access=private)
        prgs    (1,1)   double  = 0
    end
    
    methods
        function this = ImageWriter(dataset, info)
            %IMAGEWRITER 
            arguments
                dataset     (1,1)   Images
                info        (1,13)  table
            end

            this.dataset = dataset;
            this.info = info;
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
           if this.dataset.IsEmpty
               warning("ImageWriter:noImagestoWrite", ...
                   "No images could be written.");
               return;
           end

           [file, path] = uiputfile({'*.tif', 'Tiff Files (*.tif)'; ...
               '*.hdf5', 'HDF5 Files (*.tif)'; ...
               '*.mat',  'MATLAB Files (*.mat)'}, ...
               "保存图像", "captured.tif");
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
                   otherwise
               end

           end
       end
   end

   methods (Access = private)
       function saveAsTIFF(this, file)
           % call Tiff library built in MATLAB
           try
               dt = this.info.dateTime;
               dt.Format = "MM-dd HH:mm:ss.SSS";
               np = this.dataset.Size;

               %% open tiff file to write
               tifobj = Tiff(file, "w");

               %% tag struct with image information
               tagstruct.ImageWidth = this.info.width;
               tagstruct.ImageLength = this.info.height;
               tagstruct.XPosition = this.info.xOffset;
               tagstruct.YPosition = this.info.yOffset;
               tagstruct.ImageDiscription = ...
                   sprintf("BinningHorizontal=%d, BinningVertical=%d, " + ...
                   "FrameRate=%.2f, DeviceModel=%s", this.info.xBinning, ...
                   this.info.yBinning, this.info.frameRate, this.info.deviceModel);
               if this.info.bitDepth == 8
                   tagstruct.BitsPerSample = 8;
               else
                   tagstruct.BitsPerSample = 16;
               end
               tagstruct.Photometric = 1;
               tagstruct.SampleFormat = 1;
               tagstruct.ResolutionUnit = 3;
               switch this.info.resolutionUnit
                   case "mm"
                       expand_ratio = 10;
                   case "um"
                       expand_ratio = 1e4;
                   otherwise
                       expand_ratio = 1;
               end
               tagstruct.XResolution = 1/this.info.xResolution*expand_ratio;
               tagstruct.YResolution = 1/this.info.yResolution*expand_ratio;

               %% tag struct with environment information
               tagstruct.Artist = "behaviour3";
               tagstruct.Software = sprintf("MATLAB(R%s):EasyBehaviour:ImageWriter", ...
                   version('-release'));
               [~, hostname] = system('hostname');
               tagstruct.HostComputer = sprintf("host: %s, os: Windows", hostname);

               % write the first image
               [imageData, time] = this.dataset.GetFrame(1);
               tagstruct.PageNumber = [0, np];
               tagstruct.DateTime = char(dt+seconds(time));
               setTag(tifobj, tagstruct);
               write(tifobj, imageData);

               % others
               for k = 2:np
                   % read data
                   [imageData, time] = this.dataset.GetFrame(1);

                   % create new directory
                   writeDirectory(tifobj);

                   % update tag
                   tagstruct.PageNumber = [k-1, np];
                   tagstruct.DateTime = char(dt+seconds(time));

                   % save data
                   setTag(tifobj, tagstruct);
                   write(tifobj, imageData);

                   this.prgs = k/np;
               end

               %% close tiff file
               close(tifobj);

           catch ME
               rethrow(ME);
           end
       end

       function saveAsHDF5(this, file)

       end

       function saveAsMAT(this, file)

       end
   end
end
