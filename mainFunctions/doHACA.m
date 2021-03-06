function finneeStc = doHACA(finneeStc, dataset, varargin)
%% DESCRIPTION
% 1. INTRODUCTION
% DOHACA allow to build a hierarchical strcutures by classifing every
% individual PIP contained in a 'ionic profile' dataset via their
% correlation coefficient.
%
% 2. INPUT PARAMETERS
%   .required. DOHACA requires at least 2 parameters
%       finneeStc
%           is the finnee structure that contain information about the run
%           and link and indexation of the associated dat file. The
%           strcuture should have been create by function such as 
%           MZML2STRUCT
%       dataset
%           datasetis the indice to the targeted dataset (i.e. in
%           finneeStc.dataset{m}, where m is the target dataset). The
%           dataset should be a 'ionic profile' dataset
%
%   .optionals. VARARGIN describes the optional paramters.  
%       'maxProfiles' followed by an integer (default 5000)
%           Allow to limit the number of PIP based on their maximum
%           intensuty. This allow to speed up the compuational time.
%       'minCorCoef' followed by a number (default 0.9)
%           Stop the HACA when the correlation is lower than 0.9, this
%           mainly for size reason
%
% 3. EXAMPLES:
%	finneeStc = doHACA(finneeStc, 3)
%
% 5. COPYRIGHT
%   Copyright 2015-2016 G. Erny (guillaume@fe.up.pt), FEUP, Porto, Portugal
%

%% CORE OF THE FUNCTION
% 1. INITIALISATION
info.function.functionName =  'doHACA';
info.function.description{1} = 'Calculate the herarchical structure of '' dataset';
info.function.matlabVersion = '8.5.0.197613 (R2015a)';
info.function.version = '18/01/2016';
info.function.ownerContact = 'guillaume@fe.up.pt';

[parameters, options] = ...
    initFunction(nargin,  finneeStc, dataset,  varargin );
%INITFUNCTION - sub function used to verify the entries and load the optional and
% compulsory and optional parameters

m = parameters.dataset;

% 2. CHECKING THE DATA TYPE
switch finneeStc.dataset{m}.description.dataFormat
    case 'ionic profile'
        
        fidReadDat = fopen(finneeStc.path2dat, 'rb');
        fom.label = finneeStc.dataset{m}.FOM.label;
        fom.data = finneeStc.dataset{m}.FOM.data;
        [fom.data, IX] = sortrows(fom.data, -5);
        axeX = finneeStc.dataset{m}.axes.time.values;
        PIPInUse = 1:length(fom.data(:,1));
        if parameters.filter.on
            fom.filter = finneeStc.dataset{m}.description.fom.filter(IX);
            PIPInUse = find(fom.filter == 1);
        end
        matrixOfPIP = zeros(length(axeX), ...
            min(length(PIPInUse), parameters.maxPIP));
        clusters.step{1}.HL = 1;
        
        % 2. INITIALIZING THE HIERACHICAL STRUCTURE, CALCULATING THE MATRIX 
        % OF CORRELATION
        if options.display, disp('Calculating matrix of correlations'); end
        for ii = 1:length(matrixOfPIP(1,:))
            II = fom.data(PIPInUse(ii), 1);
            index = finneeStc.dataset{m}.indexInDat(II, :);
            fseek(fidReadDat, index(1), 'bof');
            
             switch index(6)
                case 2
                    curPIP = ...
                        fread(fidReadDat, [(index(2)-index(1))/(index(3)*2), index(3)], 'uint16');
                    
                case 4
                    curPIP = ...
                        fread(fidReadDat, [(index(2)-index(1))/(index(3)*4), index(3)], 'single');
                    
                case 8
                    curPIP = ...
                        fread(fidReadDat, [(index(2)-index(1))/(index(3)*8), index(3)], 'double');
             end
            matrixOfPIP(curPIP(:,1), ii) = curPIP(:,2);
            clusters.step{1}.cluster{ii} = ii;
        end
        fclose(fidReadDat);
        R = corrcoef(matrixOfPIP);
        LIntensity = fom.data(PIPInUse, 5);
        LPIP  = fom.data(PIPInUse, 1);
        
        % 4.  Initialising the CA field
        if ~isfield(finneeStc.dataset{m}, 'CA')
            finneeStc.dataset{m}.CA = {};
        end
        finneeStc.dataset{m}.CA{end+1}.name = ...
            'Dierarchical agglomerative cluster analysis.';
%        finneeStc.dataset{m}.CA{end}.dateOfCreation = datetime;
        finneeStc.dataset{m}.CA{end}.info = info;
        finneeStc.dataset{m}.CA{end}.info.parameters = parameters ;
        finneeStc.dataset{m}.CA{end}.info .error = {};

        fidWriteDat = fopen(finneeStc.path2dat, 'ab');
        cl2add.step = {};
        
        % 3. FILLING THE HIERARCHICAL STRUCTURE
        for ii = 2:length(R(:,1))
            if options.display
                fprintf('Clustering step : %d / %d \n', ii, ...
                    length(matrixOfPIP(1,:)))
            end
            max_CC = max(max(triu(R,1)));
            if max_CC <= parameters.minCC, break; end
            [linMin, colMin] = find(triu(R,1) == max_CC);
            intLin = LIntensity(linMin(1));
            intCol = LIntensity(colMin(1));
            if intLin > intCol  % take only one
                indMax = linMin(1); indMin = colMin(1);
            else
                indMax = colMin(1); indMin = linMin(1);
            end
            
            % create the clusters in step 2
            clusters.step{2}.HL = max_CC;
            clusters.step{2}.cluster = clusters.step{1}.cluster;
            profiles2Clust = [clusters.step{1}.cluster{indMin},...
                clusters.step{1}.cluster{indMax}];
            [~, ix] = sort(LIntensity(profiles2Clust), 'descend');
            clusters.step{2}.cluster{indMax} = profiles2Clust(ix);
            clusters.step{2}.cluster(indMin) = [];
            R(:, indMin) = [];
            R(indMin, :) = [];
            
            cl2add.step{end+1}.HL = clusters.step{2}.HL;
            cl2add.step{end}.index2DotDat = [ftell(fidWriteDat), 0, 1];
            data2write = zeros(1, length(clusters.step));
            for jj = 1:length(clusters.step{2}.cluster)
                if length(clusters.step{2}.cluster{jj}) >= parameters.PIPperCl
                    data2write(end+1, 1:length(clusters.step{2}.cluster{jj})) = ...
                        LPIP(clusters.step{2}.cluster{jj});
                end
            end
            data2write(1,:) = [];
            ind2rem = sum(data2write) == 0;
            data2write(:,ind2rem) = [];
            
            if isempty(data2write)
                cl2add.step{end}.index2DotDat(2) = ftell(fidWriteDat);
                cl2add.step{end}.index2DotDat(3) = 0;
            else
                fwrite(fidWriteDat, data2write, 'single');
                cl2add.step{end}.index2DotDat(2) = ftell(fidWriteDat);
                cl2add.step{end}.index2DotDat(3) = length(data2write(1,:));
            end
            
            clusters.step{1} = clusters.step{2};
        end
        
        finneeStc.dataset{m}.CA{end}.HStructure = cl2add;
        fclose(fidWriteDat);
        save(fullfile(finneeStc.info.parameters.folderOut, ...
            [finneeStc.info.parameters.fileID '.mat']), 'finneeStc')
    otherwise
        error('the dataset should be ionic profile')
end
        
%% NESTED FUNCTIONS
end

%% SUB FUNCTIONS
% 1. INITFUNCTION
% Function that get the input arguments and check for errors
function [parameters, options] = ...
    initFunction(narginIn, finneeStc, dataset, vararginIn )

% defaults parameters
parameters.minCC = 0.9;
parameters.maxPIP = 5000;
parameters.PIPperCl = 2;
options.display = 1;
parameters.dataset = dataset;
parameters.filter.on = 0;

% 1.1. Check for obligatory parameters
if narginIn < 2 % check the number of input parameters
    error('myApp:argChk', ...
        ['Wrong number of input arguments. \n', ...
        'Type help plotTrace for more information']);
elseif  ~isnumeric(dataset)
    error('myApp:argChk', ...
        ['DATASET shoud be a string. \n', ...
        'Type help MSdata2struct for more information']);
elseif ~isstruct(finneeStc)
    error('myApp:argChk', ...
        ['finneeStc shoud be a structure. \n', ...
        'Type help MSdata2struct for more information'])
end
% 1.2. Check for optional parameters
if  narginIn > 2
    SFi = 1;
    length(vararginIn)
    while SFi <= length(vararginIn)
        switch vararginIn{SFi}
            case 'maxProfiles'
                parameters.maxPIP = vararginIn{SFi+1};
                SFi = SFi + 2;
            case 'minCorCoef'
                parameters.minCC = vararginIn{SFi+1};
                SFi = SFi + 2;
            otherwise
                error('myApp:argChk', ...
                    [vararginIn{SFi} ' is not a recognized PropertyName'])
        end
    end
end
end


