% TADPOLE_SimpleForecastExample.m
%
% Example code showing how to construct a forecast in the correct format
% for a leaderboard submission to TADPOLE Challenge 2017 from the LB2 
% prediction set. The forecast simply uses a set of predefined defaults:
% 1. Likelihoods of each diagnosis (CN, MCI, AD) that depend on the
% subject's most recent clinical status. 
% 2. Forecasts of future ADAS13 score and Ventricles volume are just that
% they are unchanged from the most recent measurement, or filled with
% defaults where data is missing.
%
% ****** The purpose of the code is not to give a good forecast! ******
% 
% It is simply to show how to read in and make sense of the TADPOLE data
% sets and to output a forecast in the right format.
%
%============
% Date:
%   9 August 2017
% Authors: 
%   Daniel C. Alexander, Neil P. Oxtoby, and Razvan Valentin-Marinescu
%   University College London

%% Read in the TADPOLE data set and extract a few columns of salient information.
% Script requires that TADPOLE_D1_D2.csv is in the parent directory. Change if
% necessary
dataLocationD1D2 = '../'; % parent directory
dataLocationLB1LB2 = './';% current directory

tadpoleD1D2File = fullfile(dataLocationD1D2,'TADPOLE_D1_D2.csv');
tadpoleLB1LB2File = fullfile(dataLocationLB1LB2,'TADPOLE_LB1_LB2.csv');
outputFile = 'TADPOLE_Submission_Leaderboard_UCLTest1.csv';
errorFlag = 0;
if ~(exist(tadpoleD1D2File, 'file') == 2)
  error(sprintf(strcat('File %s does not exist. You need to download\n ',  ... 
  'it from ADNI and/or move it in the right directory'), tadpoleD1D2File))
  errorFlag = 1;
end

if errorFlag
  exit;
end

%* Read in the D1_D2 spreadsheet.
TADPOLE_Table = readtable(tadpoleD1D2File,'Delimiter','comma','TreatAsEmpty',{''},'HeaderLines',0);
% Read in the LB1_LB2 spreadsheet
LB_Table = readtable(tadpoleLB1LB2File,'Delimiter','comma','TreatAsEmpty',{''},'HeaderLines',0);

% This currently outputs a warning about datetime not being in the right
% format, but the read does work.

%* Target variables: check whether numeric and convert if necessary
targetVariables = {'DX','ADAS13','Ventricles'};
variablesToCheck = [{'RID','ICV_bl'},targetVariables]; % also check RosterID and IntraCranialVolume
for kt=1:length(variablesToCheck)
  if not(strcmpi('DX',variablesToCheck{kt}))
    if iscell(TADPOLE_Table.(variablesToCheck{kt}))
      %* Convert strings (cells) to numeric (arrays)
      TADPOLE_Table.(variablesToCheck{kt}) = str2double(TADPOLE_Table.(variablesToCheck{kt}));
    end
  end
end
%* Copy numeric target variables into arrays. Missing data is encoded as -1
% ADAS13 scores 
ADAS13_Col = TADPOLE_Table.ADAS13;
ADAS13_Col(isnan(ADAS13_Col)) = -1;
% Ventricles volumes, normalised by intracranial volume
Ventricles_Col = TADPOLE_Table.Ventricles;
Ventricles_Col(isnan(Ventricles_Col)) = -1;
ICV_Col = TADPOLE_Table.ICV_bl;
ICV_Col(Ventricles_Col==-1) = 1;
Ventricles_ICV_Col = Ventricles_Col./ICV_Col;
%* Create an array containing the clinical status (current diagnosis DX)
%* column from the spreadsheet
DXCHANGE = TADPOLE_Table.DX; % 'NL to MCI', 'MCI to Dementia', etc. = '[previous DX] to [current DX]'
DX = DXCHANGE; % Note: missing data encoded as empty string
  %* Convert DXCHANGE to current DX, i.e., the final
  for kr=1:length(DXCHANGE)
    spaces = strfind(DXCHANGE{kr},' '); % find the spaces in DXCHANGE
    if not(isempty(spaces))
      DX{kr} = DXCHANGE{kr}((spaces(end)+1):end); % extract current DX
    end
  end
CLIN_STAT_Col = DX;

%* Copy the subject ID column from the spreadsheet into an array.
RID_Col = TADPOLE_Table.RID;
RID_Col(isnan(RID_Col)) = -1; % missing data encoded as -1

%* Compute months since Jan 2000 for each exam date
EXAMDATE = cell2mat(TADPOLE_Table.EXAMDATE);
ExamMonth_Col = zeros(length(TADPOLE_Table.EXAMDATE),1);
for i=1:length(TADPOLE_Table.EXAMDATE)
    ExamMonth_Col(i) = (str2num(TADPOLE_Table.EXAMDATE{i}(1:4))-2000)*12 + str2num(TADPOLE_Table.EXAMDATE{i}(6:7));
end

% Copy the column specifying membership of LB2 into an array.
if iscell(LB_Table.LB2)
  LB2_col = str2num(cell2mat(LB_Table.LB2));
else
  LB2_col = LB_Table.LB2;
end

%% Generate the very simple forecast
display('Generating forecast ...')
%* Get the list of subjects to forecast from D1_D2 - the ordering is the
%* same as in the submission template.
lbInds = find(LB2_col);
LB2_SubjList = unique(RID_Col(lbInds));
N_LB2 = length(LB2_SubjList);

% As opposed to the proper submission, we require 84 months of forecast
% data. This is because some ADNI2 subjects from LB4 have visits even 6-7 years
% after their last ADNI1 visit from LB2.
%* Create arrays to contain the 84 monthly forecasts for each D2 subject
nForecasts = 7*12; % forecast 7 years (84 months).
% 1. Clinical status forecasts
%    i.e. relative likelihood of NL, MCI, and Dementia (3 numbers)
CLIN_STAT_forecast = zeros(N_LB2, nForecasts, 3);
% 2. ADAS13 forecasts 
%    (best guess, upper and lower bounds on 50% confidence interval)
ADAS13_forecast = zeros(N_LB2, nForecasts, 3);
% 3. Ventricles volume forecasts 
%    (best guess, upper and lower bounds on 50% confidence interval)
Ventricles_ICV_forecast = zeros(N_LB2, nForecasts, 3);

%* For this simple forecast, we will simply use the most recent exam of
%* each type from each D2 subject and base the forecast on that.
most_recent_CLIN_STAT = cell(N_LB2, 1);
most_recent_ADAS13 = zeros(N_LB2, 1);
most_recent_Ventricles_ICV = zeros(N_LB2, 1);

display_info = 0; % Useful for checking and debugging (see below)

%*** Some defaults where data is missing
%* Ventricles
  % Missing data = typical volume +/- broad interval = 25000 +/- 20000
Ventricles_typical = 25000;
Ventricles_broad_50pcMargin = 20000; % +/- (broad 50% confidence interval)
  % Default CI = 1000
Ventricles_default_50pcMargin = 1000; % +/- (broad 50% confidence interval)
  % Convert to Ventricles/ICV via linear regression
lm = fitlm(Ventricles_Col(Ventricles_Col>0),Ventricles_ICV_Col(Ventricles_Col>0));
Ventricles_ICV_typical = predict(lm,Ventricles_typical);
Ventricles_ICV_broad_50pcMargin = abs(predict(lm,Ventricles_broad_50pcMargin) - predict(lm,-Ventricles_broad_50pcMargin))/2;
Ventricles_ICV_default_50pcMargin = abs(predict(lm,Ventricles_default_50pcMargin) - predict(lm,-Ventricles_default_50pcMargin))/2;
%* ADAS13
ADAS13_typical = 12;
ADAS13_typical_lower = ADAS13_typical - 10;
ADAS13_typical_upper = ADAS13_typical + 10;

for i=1:N_LB2
    
    % Find the most recent exam for this subject
    subj_rows = find(RID_Col==LB2_SubjList(i));
    subj_exam_dates = ExamMonth_Col(subj_rows);
    [a, b] = sort(subj_exam_dates);
    most_recent_exam_ind = subj_rows(max(b));
    
    %* Identify most recent data
    % 1. Clinical status
    most_recent_CLIN_STAT{i} = CLIN_STAT_Col(most_recent_exam_ind);
    % 2. ADAS13 score
    exams_with_ADAS13 = find(ADAS13_Col(subj_rows)>0);
    if(~isempty(exams_with_ADAS13))
        [a, b] = max(subj_exam_dates(exams_with_ADAS13));
        ind = subj_rows(exams_with_ADAS13(b)); % Index of most recent visit that has an ADAS13 score
        most_recent_ADAS13(i) = ADAS13_Col(ind);
    else
        % The subject has no ADAS13 scores in the data set.
        most_recent_ADAS13(i) = -1;
    end
    % 3. Most recent Ventricles volume
    exams_with_ventsv = find(Ventricles_ICV_Col(subj_rows)>0);
    if(~isempty(exams_with_ventsv))
        [a, b] = max(subj_exam_dates(exams_with_ventsv));
        ind = subj_rows(exams_with_ventsv(b)); % Index of most recent visit that has a ventricle volume
        most_recent_Ventricles_ICV(i) = Ventricles_ICV_Col(ind);
    else
        % The subject has no ventricle volume measurement in the data set.
        most_recent_Ventricles_ICV(i) = -1;
    end
    
    %* Print out some stuff if in debug mode (set display_info=1 above).
    if(display_info)
        ExamMonth_Col(subj_rows)
        CLIN_STAT_Col(subj_rows)
        Ventricles_ICV_Col(subj_rows)
        ADAS13_Col(subj_rows)
        [i most_recent_CLIN_STAT{i} most_recent_ADAS13(i) most_recent_Ventricles_ICV(i)]
    end
    
    %* Construct status forecast
    % - Uses predefined likelihoods for each current status.
    if(strcmp(most_recent_CLIN_STAT{i}, 'NL'))
        CNp=0.75;
        MCIp=0.15;
        ADp=0.1;
    elseif(strcmp(most_recent_CLIN_STAT{i}, 'MCI'))
        CNp=0.1;
        MCIp=0.5;
        ADp=0.4;
    elseif(strcmp(most_recent_CLIN_STAT{i}, 'Dementia'))
        CNp=0.1;
        MCIp=0.1;
        ADp=0.8;
    else
        disp(['Unrecognised status '; most_recent_CLIN_STAT{i}])
        CNp=0.33;
        MCIp=0.33;
        ADp=0.34;
    end
    CLIN_STAT_forecast(i,:,1) = CNp;
    CLIN_STAT_forecast(i,:,2) = MCIp;
    CLIN_STAT_forecast(i,:,3) = ADp;

    %* Construct ADAS13 forecast 
    % - Copies most recent score. Uses a default confidence interval.
    if(most_recent_ADAS13(i)>=0)
        ADAS13_forecast(i,:,1) = most_recent_ADAS13(i);
        ADAS13_forecast(i,:,2) = max([0, most_recent_ADAS13(i)-1]); % Set to zero if best-guess less than 1.
        ADAS13_forecast(i,:,3) = most_recent_ADAS13(i)+1;
    else
        % Subject has no history of ADAS13 measurement, so we'll take a
        % typical score of 12 with wide confidence interval +/-10.
        ADAS13_forecast(i,:,1) = ADAS13_typical;
        ADAS13_forecast(i,:,2) = ADAS13_typical_lower;
        ADAS13_forecast(i,:,3) = ADAS13_typical_upper;
    end
    
    %* Construct Ventricles volume forecast
    % - Copies most recent measurement. Uses a default confidence interval.
    if(most_recent_Ventricles_ICV(i)>0)
        Ventricles_ICV_forecast(i,:,1) = most_recent_Ventricles_ICV(i);
        Ventricles_ICV_forecast(i,:,2) = most_recent_Ventricles_ICV(i) - Ventricles_ICV_default_50pcMargin;
        Ventricles_ICV_forecast(i,:,3) = most_recent_Ventricles_ICV(i) + Ventricles_ICV_default_50pcMargin;
    else
        % Subject has no imaging history, so we'll take a typical ventricle
        % volume of 25000 with wide confidence interval +/-20000.
        Ventricles_ICV_forecast(i,:,1) = Ventricles_ICV_typical;
        Ventricles_ICV_forecast(i,:,2) = Ventricles_ICV_typical - Ventricles_ICV_broad_50pcMargin;
        Ventricles_ICV_forecast(i,:,3) = Ventricles_ICV_typical + Ventricles_ICV_broad_50pcMargin;
    end    
        
end

%% Now construct the forecast spreadsheet and output it.
display(sprintf('Constructing the output spreadsheet %s ...', outputFile))
startDate = datenum('01-Jan-2018');

submission_table =  cell2table(cell(N_LB2*nForecasts,12), ...
  'VariableNames', {'RID', 'ForecastMonth', 'ForecastDate', ...
  'CNRelativeProbability', 'MCIRelativeProbability', 'ADRelativeProbability', ...
  'ADAS13', 'ADAS1350_CILower', 'ADAS1350_CIUpper', ...
  'Ventricles_ICV', 'Ventricles_ICV50_CILower', 'Ventricles_ICV50_CIUpper' });
%* Repeated matrices - compare with submission template
submission_table.RID = reshape(repmat(LB2_SubjList, [1, nForecasts])', N_LB2*nForecasts, 1);
submission_table.ForecastMonth = repmat((1:nForecasts)', [N_LB2, 1]);
%* First subject's submission dates
for m=1:nForecasts
  submission_table.ForecastDate{m} = datestr(addtodate(startDate, m-1, 'month'), 'yyyy-mm');
end
%* Repeated matrices for submission dates - compare with submission template
submission_table.ForecastDate = repmat(submission_table.ForecastDate(1:nForecasts), [N_LB2, 1]);

%* Pre-fill forecast data, encoding missing data as NaN
nanColumn = nan(size(submission_table.CNRelativeProbability));
submission_table.CNRelativeProbability = nanColumn;
submission_table.MCIRelativeProbability = nanColumn;
submission_table.ADRelativeProbability = nanColumn;
submission_table.ADAS13 = nanColumn;
submission_table.ADAS1350_CILower = nanColumn;
submission_table.ADAS1350_CIUpper = nanColumn;
submission_table.Ventricles_ICV = nanColumn;
submission_table.Ventricles_ICV50_CILower = nanColumn;
submission_table.Ventricles_ICV50_CIUpper = nanColumn;

%*** Paste in month-by-month forecasts **
%* 1. Clinical status
  %*  a) CN probabilities
col = 4;
t = CLIN_STAT_forecast(:,:,1)';
col = submission_table.Properties.VariableNames(col);
submission_table{:,col} = t(:);
  %*  b) MCI probabilities
col = 5;
t = CLIN_STAT_forecast(:,:,2)';
col = submission_table.Properties.VariableNames(col);
submission_table{:,col} = t(:);
  %*  c) AD probabilities
col = 6;
t = CLIN_STAT_forecast(:,:,3)';
col = submission_table.Properties.VariableNames(col);
submission_table{:,col} = t(:);
%* 2. ADAS13 score
col = 7;
t = ADAS13_forecast(:,:,1)';
col = submission_table.Properties.VariableNames(col);
submission_table{:,col} = t(:);
  %*  a) Lower and upper bounds (50% confidence intervals)
col = 8;
t = ADAS13_forecast(:,:,2)';
col = submission_table.Properties.VariableNames(col);
submission_table{:,col} = t(:);
col = 9;
t = ADAS13_forecast(:,:,3)';
col = submission_table.Properties.VariableNames(col);
submission_table{:,col} = t(:);
%* 3. Ventricles volume (normalised by intracranial volume)
col = 10;
t = Ventricles_ICV_forecast(:,:,1)';
col = submission_table.Properties.VariableNames(col);
submission_table{:,col} = t(:);
  %*  a) Lower and upper bounds (50% confidence intervals)
col = 11;
t = Ventricles_ICV_forecast(:,:,2)';
col = submission_table.Properties.VariableNames(col);
submission_table{:,col} = t(:);
col = 12;
t = Ventricles_ICV_forecast(:,:,3)';
col = submission_table.Properties.VariableNames(col);
submission_table{:,col} = t(:);

%* Convert all numbers to strings
hdr = submission_table.Properties.VariableNames;
for k=1:length(hdr)
  if ~iscell(submission_table.(hdr{k}))
    %submission_table{1:10,hdr{k}} = varfun(@num2str,submission_table{1:10,hdr{k}},'OutPutFormat','cell');
    submission_table.(hdr{k}) = strrep(cellstr(num2str(submission_table{:,hdr{k}})),' ','');
  end
end

%* Use column names that match the submission template
columnNames = {'RID', 'Forecast Month', 'Forecast Date',...
'CN relative probability', 'MCI relative probability', 'AD relative probability',	...
'ADAS13',	'ADAS13 50% CI lower', 'ADAS13 50% CI upper', 'Ventricles_ICV', ...
'Ventricles_ICV 50% CI lower',	'Ventricles_ICV 50% CI upper'};
%* Convert table to cell array to write to file, line by line
%  This is necessary because of spaces in the column names: writetable()
%  doesn't handle this.
tableCell = table2cell(submission_table);
tableCell = [columnNames;tableCell];
%* Write file line-by-line
fid = fopen(outputFile,'w');
for i=1:size(tableCell,1)
  fprintf(fid,'%s\n', strjoin(tableCell(i,:), ','));
end
fclose(fid);
