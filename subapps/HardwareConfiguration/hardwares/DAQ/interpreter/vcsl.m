function ctbl = vcsl(file, map)
%VCSL This is vcsl(value control script language) interpreter, the vcsl 
% source file will be explained to control array as control table
% Input:
%   - file: string scalar, indicate the source file absolute location
%   - map: dictionary object, valve label map to inner identity (hard code)
% Output:
%   - ctbl: n-by-4 table, format as [code, mixing, cmd, delay]

% VCSL Language Interpreter
% Author: Weihan Li
% Version: 1.1.0
% Release Date: 2024/11/07

arguments
    file    (1,1)   string      {mustBeFile}    % 
    map     (1,1)   dictionary                  % string -> 1-by-n logical array
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

ctbl = table('Size', [0,4], 'VariableTypes', {'string', 'cell', 'double', 'double'}, ...
    'VariableNames', {'code', 'mixing', 'cmd', 'delay'});
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
    cmdl = cmdq(n);
    switch cmdl
        case KWD_CLOSE_
            ctbl = [ctbl; {KWD_CLOSE_, {1}, map{KWD_CLOSE_}, 1}];    %#ok<AGROW> % delay as 1 (constant)
        otherwise
            % parse final command
            cmdl = cmdl.split(":");
            code = cmdl(1).extractBetween("[","]");
            args = cmdl(2).split(",").erase(" ");

            % parse 'delay' and validate
            delay = str2double(args(1));
            if isnan(delay) || isinf(delay)
                throw(MException("vcsl:invalidDelay","Line:""%s"" with " + ...
                    "invalid delay time detected.", cmdq(n)));
            end

            % parse mixing and validate
            if isscalar(args)
                mixing = 1;
            else
                mixing = reshape(str2double(args(2).split("&")),1,[]);
            end
            
            if any(isnan(mixing)|isinf(mixing)|(mixing<=0)|(mixing>1))
                throw(MException("vcsl:invalidMixing","Line:""%s"" with " + ...
                    "invalid mixing ratio.", cmdq(n)));
            end
            
            if sum(mixing) ~= 1
                throw(MException("vcsl:invalidMixing","Line:""%s"" with " + ...
                    "invalid mixing sum: %.2f.", cmdq(n), sum(mixing)));
            end
            
            % parse code and validate
            lcmd = code.split("&");
            if numel(lcmd) ~= numel(mixing)
                throw(MException("vcsl:invalidCode","Line:""%s"" with " + ...
                    "inconsistent number between code and mixing.", cmdq(n)));
            end
            if ~all(ismember(lcmd, [map.keys("uniform"); lblmap.keys("uniform")]))
                throw(MException("vcsl:invalidCode","Line:""%s"" with " + ...
                    "undefined symbol in MAP.", cmdq(n)));
            end

            bcmd = map{KWD_CLOSE_}; % logical 0

            % composite function, omit for-if cross-cut for such code
            for q = 1:numel(lcmd)
                if isempty(lblmap)
                    bcmd = bcmd | map{lcmd(q)};
                else
                    bcmd = bcmd | map{lblmap(lcmd(q))};
                end
            end

            ctbl = [ctbl; {code, {mixing}, bcmd, delay}]; %#ok<AGROW>
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
        nloop = str2double(cmd(2));
        if isPositiveIntegerValuedNumeric(nloop)
            edr = [edr; nloop]; %#ok<AGROW>
            ptr = ptr + 1;  % move pointer
        else
            throw(MException("vcsl:invalidLoopNumber", ...
                "Loop number must be finite positive integer."));
        end
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
