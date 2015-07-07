function Vanilla_CLNF_best_bbox()

addpath('../PDM_helpers/');
addpath('../fitting/normxcorr2_mex_ALL');
addpath('../fitting/');
addpath('../CCNF/');
addpath('../models/');

% Replace this with the location of in 300 faces in the wild data
if(exist([getenv('USERPROFILE') '/Dropbox/AAM/test data/'], 'file'))
    root_test_data = [getenv('USERPROFILE') '/Dropbox/AAM/test data/'];    
else
    root_test_data = 'F:/Dropbox/Dropbox/AAM/test data/';
end

% load the images to detect landmarks of

csv_loc = 'D:\JANUS_training\aflw\aflw_68_dev.csv';
csv_meta_loc = 'D:\JANUS_training\aflw/metadata_68_dev.csv';
root_loc = 'D:\Datasets\AFLW/';

[images, detections, labels] = Collect_imgs(csv_loc, csv_meta_loc, root_loc);

%% loading the patch experts
   
clmParams = struct;

clmParams.window_size = [25,25; 23,23; 21,21;];

clmParams.numPatchIters = size(clmParams.window_size,1);

[patches] = Load_Patch_Experts( '../models/general/', 'ccnf_patches_*_general.mat', [], [], clmParams);
%% Fitting the model to the provided image

verbose = true; % set to true to visualise the fitting
output_root = './dev_fit_bbox_perfect/';

% the default PDM to use
pdmLoc = ['../models/pdm/pdm_68_aligned_wild.mat'];

load(pdmLoc);

pdm = struct;
pdm.M = double(M);
pdm.E = double(E);
pdm.V = double(V);

% the default model parameters to use
clmParams.regFactor = 25;               
clmParams.sigmaMeanShift = 2;
clmParams.tikhonov_factor = 5;

clmParams.startScale = 1;
clmParams.num_RLMS_iter = 10;
clmParams.fTol = 0.01;
clmParams.useMultiScale = true;
clmParams.use_multi_modal = 1;
clmParams.multi_modal_types  = patches(1).multi_modal_types;
   
% for recording purposes
experiment.params = clmParams;

num_points = numel(M)/3;

errors = zeros(numel(images),1);
shapes_all = zeros(size(labels,2),size(labels,3), size(labels,1));
labels_all = zeros(size(labels,2),size(labels,3), size(labels,1));
errors_normed = zeros(numel(images),1);
lhoods = zeros(numel(images),1);
all_lmark_lhoods = zeros(num_points, numel(images));
all_views_used = zeros(numel(images),1);

% Use the multi-hypothesis model, as bounding box tells nothing about
% orientation
load('../bounding_box_mapping/AFLW_gt_bbox.mat');

tic
for i=1:numel(images)

    image = imread(images(i).img);
    image_orig = image;
    
    if(size(image,3) == 3)
        image = rgb2gray(image);
    end              

    load('../bounding_box_mapping/mappings.mat');
    % view variable is loaded in from the mappings
    shapes = zeros(num_points, 2, size(views,1));
    ls = zeros(size(views,1),1);
    lmark_lhoods = zeros(num_points,size(views,1));
    views_used = zeros(num_points,size(views,1));
    global_params_all = zeros(6, size(views,1));

    % Find the best orientation
    for v = 1:size(views,1)
        valid_labels = labels(i,:,1) ~= 0;
        % Correct the widths
        bbox = bboxes_gt(i,:);

        if(sum(bbox) == 0)
           continue; 
        end
        
        bbox = bbox + 1;
        
        [shapes(:,:,v),global_params_all(:,v),~,ls(v),lmark_lhoods(:,v),views_used(v)] = Fitting_from_bb(image, [], bbox, pdm, patches, clmParams, 'orientation', views(v,:));

    end

    [lhood, v_ind] = max(ls);

    lmark_lhood = lmark_lhoods(:,v_ind);

    shape = shapes(:,:,v_ind);
    view_used = v_ind;
    global_params = global_params_all(:,v_ind);

    all_lmark_lhoods(:,i) = lmark_lhood;
    all_views_used(i) = view_used;
    
%     [~,view] = min(sum((patches(1).centers * pi/180 - repmat(global_params(2:4)', size(patches(1).centers,1), 1)).^2,2));visibilities = logical(patches(1).visibilities(view,:))';imshow(image);hold on;plot(shape(visibilities,1), shape(visibilities,2), '.r');hold off;

    % shape correction for matlab format
    shapes_all(:,:,i) = shape;
    labels_all(:,:,i) = labels(i,:,:);

    if(mod(i, 200)==0)
        fprintf('%d done\n', i );
    end

    valid_points =  sum(squeeze(labels(i,:,:)),2) > 0;
    valid_points(1:17) = 0;

    % Center the pixel
    actualShape = squeeze(labels(i,:,:)) - 0.5;
    
    errors(i) = sqrt(mean(sum((actualShape(valid_points,:) - shape(valid_points,:)).^2,2)));      
    width = max(((max(actualShape(valid_points,1)) - min(actualShape(valid_points,1)))),(max(actualShape(valid_points,2)) - min(actualShape(valid_points,2))));
    errors_normed(i) = errors(i)/width;
    lhoods(i) = lhood;
    if(verbose)
        [height_img, width_img,~] = size(image_orig);
        width = max(shape(:,1)) - min(shape(:,1));
        height = max(shape(:,2)) - min(shape(:,2));

        img_min_x = max(int32(min(shape(:,1))) - width/3,1);
        img_max_x = min(int32(max(shape(:,1))) + width/3,width_img);

        img_min_y = max(int32(min(shape(:,2))) - height/3,1);
        img_max_y = min(int32(max(shape(:,2))) + height/3,height_img);

        shape(:,1) = shape(:,1) - double(img_min_x);
        shape(:,2) = shape(:,2) - double(img_min_y);

        image_orig = image_orig(img_min_y:img_max_y, img_min_x:img_max_x, :);    

        % valid points to draw (not to draw
        % occluded ones)
        [~,view] = min(sum((patches(1).centers * pi/180 - repmat(global_params(2:4)', size(patches(1).centers,1), 1)).^2,2));
        visibilities = logical(patches(1).visibilities(view,:))';        

        f = figure('visible','off');
        %f = figure;
        try
        if(max(image_orig(:)) > 1)
            imshow(double(image_orig)/255, 'Border', 'tight');
        else
            imshow(double(image_orig), 'Border', 'tight');
        end
        axis equal;
        hold on;
        
        plot(shape(visibilities,1), shape(visibilities,2),'.r','MarkerSize',20);
        plot(shape(visibilities,1), shape(visibilities,2),'.b','MarkerSize',10);
%                                         print(f, '-r80', '-dpng', sprintf('%s/%s%d.png', output_root, 'fit', i));
        print(f, '-djpeg', sprintf('%s/%s%d.jpg', output_root, 'fit', i));
%                                         close(f);
        hold off;
        close(f);
        catch warn

        end
    end

end
toc
experiment.errors = errors;
experiment.errors_normed = errors_normed;
experiment.lhoods = lhoods;
experiment.shapes = shapes_all;
experiment.labels = labels_all;
experiment.aflw_error = compute_error(labels, shapes_all - 0.5, detections);
experiment.all_lmark_lhoods = all_lmark_lhoods;
experiment.all_views_used = all_views_used;
% save the experiment
if(~exist('experiments', 'var'))
    experiments = experiment;
else
    experiments = cat(1, experiments, experiment);
end
fprintf('experiment %d done: mean normed error %.3f median normed error %.4f\n', ...
    numel(experiments), mean(errors_normed), median(errors_normed));

%%
output_results = 'results/results_dev_clnf_ideal_bbox.mat';
save(output_results, 'experiments');
    
end