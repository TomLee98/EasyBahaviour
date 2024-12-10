function folder_ = findTmpFolder(dataSizeBytes)
%FINDTMPFOLDER This function find a temporary folder in a disk part, which
%could contains the memory mapping files
% input:
%   - dataSizeBytes: 1-by-1 not nan double, indicate estimated
%       bytes of storage, inf for 'as more as possible'
% output:
%   - folder: 1-by-1 string, the temporary folder
arguments
    dataSizeBytes   (1,1)   double  {mustBeNonmissing} = inf
end

import java.io.*;
import javax.swing.filechooser.*;
import java.lang.*;

warning('off', 'MATLAB:MKDIR:DirectoryExists');

if ispc()
    files_ = File.listRoots();
    disk_table = table('Size',[numel(files_), 5], ...
        'VariableTypes',{'string','double','logical','logical','logical'}, ...
        'VariableNames',{'letter','free_size','readable','writable','is_local'});
    for p = 1:numel(files_)
        disk_table.letter(p) = string(files_(p).getPath());
        disk_table.free_size(p) = files_(p).getFreeSpace();
        disk_table.readable(p) = files_(p).canRead();
        disk_table.writable(p) = files_(p).canWrite();
        disk_table.is_local(p) = is_local_disk(files_(p));
    end

    % disk scheduling: find the maximum disk part as temporary root
    vp = disk_table.readable & disk_table.writable ...
        & disk_table.is_local;
    disk_table = disk_table(vp, :);
    [fs, idx] = max(disk_table.free_size);
    if ~isinf(dataSizeBytes) && (fs < dataSizeBytes)
        throw(MException("mQueueHD:invalidFileSize", ...
            "No enough hard drive space. [%s]:%.1f GB, Require %.1f GB.", ...
            disk_table.letter, round(fs/(1024^3), 1), round(dataSizeBytes/(1024^3), 1)));
    end

    folder_ = [disk_table.letter(idx).char(), 'EBCache', filesep];

    try
        mkdir(folder_);
        fileattrib(folder_, '+h', '', 's');
    catch ME
        rethrow(ME);
    end
else
    throw(MException("mQueueHD:invalidOperationSystem", ...
        "Only Windows support 'findtmpfolder'."));
end

warning('on', 'MATLAB:MKDIR:DirectoryExists');

    function tf_ = is_local_disk(file_)
        % NOTE: This function can't distinguish movable disk and
        % local disk
        % TODO:

        % construct java object
        lang = System.getProperty("user.language");
        fileSystemView = FileSystemView.getFileSystemView();

        if string(lang) == "zh"
            marker = "本地磁盘";
        else
            marker = "LocalDisk"; % ?? not confirm
        end
        diskType = fileSystemView.getSystemTypeDescription(file_);
        tf_ = (string(diskType) == marker);
    end
end

