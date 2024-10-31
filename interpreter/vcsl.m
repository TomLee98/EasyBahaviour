function ctbl = vcsl(file, map)
%VCSL This is vcsl(value control script language) interpreter, the vcsl 
% source file will be explained to control array as control table
% Input:
%   - file: string scalar, indicate the source file absolute location
%   - map: dictionary object, valve label map to inner identity (hard code)
% Output:
%   - ctbl: n-by-2 table, format as [cmd, delay]

arguments
    file    (1,1)   string      {mustBeFile}
    map     (1,1)   dictionary  = dictionary()  % string -> 1-by-n logical array
end

%% KEYWORD DEFINATION
KWD_MAP_ = "MAP";
KWD_CLOSE_ = "CLOSE";
KWD_LOOP_ = "LOOP";

%%
% parse file
try
    src = readlines(file, "EmptyLineRule","skip","WhitespaceRule","trimtrailing", ...
        "Whitespace",' \b\t#');
catch ME
    rethrow(ME);
end

ctbl = table('Size', [0,2], 'VariableTypes', {'double', 'double'}, ...
    'VariableNames', {'cmd', 'delay'});
lblmap = dictionary();
cmdq = [];          % full commands queue, n-by-1 string array

ptr = 1;
while ptr <= numel(src)
    % read a line
    cmd = src(ptr);
    if cmd.contains("#")
        % remove comment text
        cmd = cmd.extractBefore("#").erase(" ");
    end
    if isequal(cmd, "")
        ptr = ptr + 1;
        continue;       % skip empty line
    end

    % parse the code, branch by keyword
    if cmd.contains(KWD_MAP_)
        vlmap = cmd.erase(" ").extractBetween("{","}").split(",").split(":");
        % configure map: string -> double(positive integer)
        if isscalar(vlmap) && isequal(vlmap, "")
            % empty parse
        else
            % non-empty parse
            lblmap(vlmap(:,1)) = vlmap(:,2);
        end

        ptr = ptr + 1;
    elseif cmd.contains(KWD_CLOSE_)
        cmdq = [cmdq; KWD_CLOSE_]; %#ok<AGROW>

        ptr = ptr + 1;
    elseif cmd.contains(KWD_LOOP_)
        [lcmd, dptr] = parseLoop(src(ptr:end), KWD_LOOP_);
        src = [src(1:ptr-1); lcmd];
        cmdq = [cmdq; lcmd(1:dptr)]; %#ok<AGROW>

        ptr = ptr + dptr;
    else
        ptr = ptr + 1;
    end
end

% remove pre-space
cmdq = cmdq.erase(" ");

% post-modify cmdq to ctbl
for n = 1:numel(cmdq)
    cmd = cmdq(n);
    switch cmd
        case KWD_CLOSE_
            ctbl = [ctbl; {map{KWD_CLOSE_}, 0}];    %#ok<AGROW> % delay as 0
        otherwise
            % parse final command
            cmd = cmd.split(":");
            lcmd = cmd(1).extractBetween("[","]").split("&");
            bcmd = map{KWD_CLOSE_}; % logical 0

            % composite function, omit for-if cross-cut for such code
            for q = 1:numel(lcmd)
                if isempty(lblmap)
                    bcmd = bcmd | map{lcmd(q)};
                else
                    bcmd = bcmd | map{lblmap(lcmd(q))};
                end
            end

            ctbl = [ctbl; {bcmd, str2double(cmd(2))}]; %#ok<AGROW>
    end
end


end

% parseLoop
% parse loop code, output code length
function [cmd, dp] = parseLoop(src, kwd_loop)
ptr = 1;
lsptr = [];     % stack head pointer
edr = [];       % expand ratio (repeat times)

while ptr <= numel(src)
    cmd = src(ptr);
    if cmd.contains(kwd_loop)
        cmd = cmd.extractBetween("<",">").split(":");
        edr = [edr; str2double(cmd(2))]; %#ok<AGROW>
        ptr = ptr + 1;  % move pointer
    elseif isequal(cmd.erase(" "), "{")
        % push ptr into  syntax stack
        lsptr = [lsptr; ptr]; %#ok<AGROW>
        ptr = ptr + 1;  % move pointer
    elseif isequal(cmd.erase(" "), "}")
        % proximity principle for block parse and replace
        src_block = src(lsptr(end)+1:ptr-1);
        idcmd = repmat(src_block.erase("\t"), edr(end), 1);
        src = [src(1:lsptr(end)-2); idcmd; src(ptr+1:end)]; % expand src
        ptr = ptr + (numel(idcmd)-(ptr-lsptr(end)+1));  % move pointer
        dp = ptr-1;     % expand size (loop true size)
        lsptr(end) = [];    % pop
        edr(end) = [];
    else
        ptr = ptr + 1;  % move pointer
    end

    if isempty(lsptr)&&isempty(edr)
        break;
    end
end

cmd = src;
end
