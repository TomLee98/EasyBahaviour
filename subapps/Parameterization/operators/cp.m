function mc = cp(frame, boxes)
%CP This function calculate the maximum connected region in a boxed image
% Input:
%   - frame: 1-by-2 cell, field as {image, time}, image is uint8 or uint16
%           matrix, time is nonnegtive double scalar
%   - boxes: 1-by-1 dictionary, <string> -> <cell>, id |-> [x,y,w,h,p]
% Output:
%   - mc: 1-by-1 dictionary, <string> -> <cell>, id |-> [x,y,t]

arguments
    frame   (1,2)   cell
    boxes   (1,1)   dictionary
end

mc = configureDictionary("string", "cell");

if boxes.isConfigured && boxes.numEntries > 0
    img = frame{1};
    time_stamp = frame{2};
    for key = boxes.keys("uniform")'
        % use global threshold for background extraction
        box = ceil(boxes{key}(1:4));
        bw = imbinarize(img(box(2):box(2)+box(4)-1, box(1):box(1)+box(3)-1), "global");

        % inner coordination + offset
        mc_x = sum(sum(bw, 1).*(0.5:box(3)-0.5))/sum(bw, "all") + box(1);
        mc_y = sum(mean(sum(bw, 2).*(0.5:box(4)-0.5)'))/sum(bw, "all") + box(2);

        mc(key) = {ceil([mc_x, mc_y, time_stamp])};
    end
end

end

