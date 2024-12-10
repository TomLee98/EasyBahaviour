function file_ = newRandFileName(folder_)
% generate file name code: 18 chars hash
% P < 1e-22 for same file name
code_idx = [randi(26,1,6)+64, randi(26,1,6)+96, randi(10,1,6)+47];
code_idx = code_idx(randperm(18));

% random suffix for avoiding same filename
% and hidden the file information
filename_ = char(code_idx);

if isstring(folder_), folder_ = folder_.char(); end

file_ = [folder_, filesep, filename_, '.mat'];
end
