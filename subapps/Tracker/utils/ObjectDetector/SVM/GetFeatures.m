function [feature, img_bw] = GetFeatures(img, option)
%GETFEATURES This function get features in one boxed image (image block)
% and call LittleObjectDetector static function: extractFeature
% This function works look like LittleObjectDetector private function: getFeatures
% Input:
%   - img: m-by-n uint8/uint16 blocked image, contains only one object
% Output:
%   - feature: 1-by-s feature vector

% edge detection
[~, th] = edge(img, option.edgealg);
img_bw_pre = edge(img, option.edgealg, th * option.fudgefac);

% dilate object
% we keep holes inner object as one of detection features
se90 = strel("line",3,90); se0 = strel("line",3,0); % minimal cross
img_bw_pre = imdilate(img_bw_pre,[se90 se0]);

% fill holes
img_bw_post = imfill(img_bw_pre, "holes");

% remove possible connected object at border
img_bw_post = imclearborder(img_bw_post, 4);

% check if object has been removed
if any(img_bw_post, "all")
    % smooth for better foreground
    seD = strel('diamond',1);
    img_bw_post = imerode(img_bw_post, seD);    % erode only once

    % cross for final mask(with inner holes)
    img_bw = img_bw_post.*img_bw_pre;

    % detect features
    feature = extractFeature(img_bw, ...
        "ALL");
else
    warning("GetFeatures:objectLost", "No object detected, may be removed by " + ...
        "imclearborder.");
    feature = [];
    img_bw = img_bw_post;
end

end

