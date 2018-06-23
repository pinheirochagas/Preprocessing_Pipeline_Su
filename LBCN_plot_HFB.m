function signal_all = LBCN_plot_HFB(evtfile,D,bch,exclude,conditionList,plot_cond,save_print,type,pre_defined_bad, atf_check,twsmooth,twbc)
%   Computes and plots the HFB power.
%
%   Input:      evtfile:    eventsSODATA_XXX.mat generated by
%               LBCN_read_events_diod_sodata function that contains events.categories info.
%               D:          eM*.mat generated by
%               LBCN_epoch_bc function. This is the epoched data in SPM
%               MEEG format. It can also be a [C x M x N] matrix of epoched data (in real time order),
%               where C = channels, M = data sample length, N = trials.
%               bch:        bad channel index (multiple sessions stored in
%               cells). Optional.
%               exclude:    pathological event indicies generated by
%               exclude_trial function. Optional.
%               condList:   list of conditions for each trial. Optional.
%               plot_cond:  which conditions to plot. Could be a set of cell
%               arrays containing the name of the condition,or the index of the condition.
%               Can also be 'subcat' (for VTC). Optional.
%               save_print:  put 1 if want the figures to be saved. Default
%               0, the results will be plotted and paused for inspection.
%               type:       1 = efficient plot using FFT.
%                           2 = t-f plot using wavelet.
%               pre_defined_bad:
%   Output:     figures.
%   -----------------------------------------
%   =^._.^=     Su Liu
%
%   suliu@standord.edu
%   -----------------------------------------

if nargin<1 || isempty(evtfile)
    fprintf('%s\n','---- Please select eventsSODATA file or Epoched_data ----');
    [filename,pathname] = uigetfile({'*.mat','Data format (*.mat)'},...
        'MultiSelect', 'on');
    fname = fullfile(pathname,filename);
    if iscell(fname)
        evtfile = fname;
    else
        L = load(fname);
        if isfield(L,'beh_fp')
            D = L.D;
            evtfile = L.evtfile;
            bch = L.bch;
            signal_all = L.beh_fp;
            labels = L.labels;
            plot_cond = L.plot_cond;
            fprintf('%s\n','-------- Epoched signal loaded --------');
        elseif isfield(L,{'DAT','evtfile','exclude','conditionList','bch'})
            D = L.DAT;
            evtfile = L.evtfile;
            bch = L.bch;
            exclude = L.exclude;
            exclude_ts = L.exclude_ts;
            conditionList = L.conditionList;
            plot_cond = L.plot_cond;
            fprintf('%s\n','-------- Epoched data loaded --------');
            signal_all = LBCN_plot_HFB(evtfile,D,bch,exclude,conditionList,plot_cond,[],[],exclude_ts);
            return;
        elseif length(size(getfield(L,char(fieldnames(L))))) == 3
            data = getfield(L,char(fieldnames(L)));
            fprintf('%s\n','-------- Data in matrix. Will compute the HFB only --------');
            signal_all = compute_HFB(data);
            return;
        else
            evtfile{1} = fname;
        end
    end
end
if ~exist('signal_all','var')
    if nargin<2 || isempty(D)
        for i = 1:length(evtfile)
            [filepath,name,~] = fileparts(evtfile{i});
            fixind = regexp(name,'DCchans')+8;
            [name2] = find_file(filepath,'/eM*.mat',name(fixind:end));
%             en = strcat(filepath,'/eM*.mat');
%             match = [];
%             S = dir(en);
%             for k = 1:numel(S)
%                 N{k} = S(k).name;
%                 if contains(N{k}, name(21:end))
%                     match = [match, k];
%                 end
%             end
            
            if ~isempty(name2)
                %name2 = fullfile(filepath,N{match(end)});
                D{i} = spm_eeg_load(name2);
                continue;
            else
                fprintf('%s\n','-------- Data file not found --------');
                [filename,pathname] = uigetfile({'*.mat','Data format (*.mat)'},...
                    'MultiSelect', 'on');
                names = fullfile(pathname,filename);
                if ~iscell(names)
                    n{1}=names;
                    names = n;
                end
                for ii = 1:length(evtfile)
                    try
                        D{ii} = spm_eeg_load(names{ii});
                    catch
                        load(names{i});
                    end
                end
                fprintf('%s\n','-------- Data loaded --------');
                break;
            end
        end
    end
    
    if nargin<3 || isempty(bch)
        bch = cell(length(evtfile),1);
    end
    
    if nargin<6 || isempty(plot_cond)
            task = identify_task(evtfile{1});
            task_config(task);
        plot_cond = 1:D{1}.nconditions;
    end
end
if nargin<4 || isempty(exclude)
    exclude = repmat({cell(1,D{1}.nchannels)},length(evtfile),1);
end

if nargin<5 || isempty(conditionList)
    for i=1:length(evtfile)
        conditionList{i} = conditions(D{i});
    end
end
if nargin<7 || isempty(save_print)
    save_print = 0;
end
if nargin<8 || isempty(type)
    type = 1;
end
if nargin<9 || isempty(pre_defined_bad)
    pre_defined_bad = repmat({[]},length(evtfile),1);
end
if nargin<10 || isempty(atf_check)
    atf_check = 3;
end
if ~exist('twsmooth','var')
if nargin<11 || isempty(twsmooth)
    twsmooth = [-200 800];
end
if nargin<12 || isempty(twbc)
    twbc = [-200 0];
end
end
merge = 0;
fs = fsample(D{1});
labs = D{1}.condlist;
if ~exist('labels','var')
    labels = labs;
end
if iscell(plot_cond)
    if any(strcmp(plot_cond,'subcat'))
        labels = [{'faces'} {'bodies'} {'buildings & scenes'} {'numbers'} ...
            {'words'} {'logos & shapes'} {'other'}];
        plot_cond = [5 4 1 2 3 6];
        merge = 1;
    else
        for i = length(plot_cond)
            condid(i) = find(strcmpi(labs,plot_cond{i}));
        end
        plot_cond = condid;
    end
end
Nt = length(plot_cond);
cn = D{1}.nchannels;
time_start = min(time(D{1}));
time_end = max(time(D{1}));
total_plot = cell(Nt,1);
total_raw = cell(length(evtfile),1);
t = time_start:(time_end-time_start)/(D{1}.nsamples-1):time_end;
window = round((twsmooth(1) - time_start*fs) +1 : ((twsmooth(1) - time_start*fs) + (twsmooth(2) - twsmooth(1))));
window_bc = round((twbc(1) - time_start*fs) +1 : ((twbc(1) - time_start*fs) + (twbc(2) - twbc(1))));
fbands = zeros(11,2);

for jj = 1:11
    fbands(jj,:) = [70+10*(jj-1) 70+10*(jj)];
end

if ~exist('signal_all','var')
    fprintf('%s\n','------ Calculating HFB ------')
    %% re-arrange the data, take out excluded trials%%%%%%%%%%
    sdata = cell(1,length(evtfile));
    sdata2 = cell(1,length(evtfile));
    for N=1:length(evtfile)
        dsp = strcat('File ',' ',num2str(N),' / ',' ',num2str(length(evtfile)));
        fprintf('%s\n',dsp);
        load(evtfile{N});
        data = D{N}(:,:,:);
        pre_defined = pre_defined_bad{N};
        %% Just to test something. Comment this 
        bc_type = 'z';
        type = 1;
        atf_check = 3;
        %% Signal 2 is the other un-chosen baseline correction method. (Just get ready for the plotting)
        [signal, signal2] = compute_HFB(data, fs, type, fbands, atf_check, bc_type,window_bc ,pre_defined, window);
        cn = size(data,1);
        ts=[];
        for i=1:length(events.categories)
            ts=[ts events.categories(i).start];
        end
        [~,A]=sort(ts);
        sdata{N} = signal(:,:,A);
        sdata2{N} = signal2(:,:,A);
        
        %% In case it crashes 0_0
        assignin ('base','Signal',sdata{N});
        assignin ('base','Signal2',sdata2{N});
        %% Some arrangements
        for i = 1:cn
            m = 1;
            dt=squeeze(sdata{N}(i,:,:));
            dt2=squeeze(sdata2{N}(i,:,:));
                try
                    ex=exclude{N}{i}(1,all(exclude{N}{i}));
                catch
                    ex = [];
                end
                con=conditionList{N};
                con(ex)=[];
                dt(:,ex)=[];
                dt2(:,ex)=[];
            curr_id=false(Nt,size(dt,2));
            for k = plot_cond
                %ex=[];
                %curr_cond=labs(plot_cond(k));
                curr_cond=labels(k);
                
                if merge
                    if ~strcmp(curr_cond,'other')
                        if strcmp(curr_cond,'words')
                            curr_id(k,:)=strcmpi(con,curr_cond);
                        else
                            curr_id(k,:)=contains(string(con),strsplit(string(curr_cond)));
                        end
                    else
                        curr_id(k,:)=~sum(curr_id);
                    end
                else
       
                     curr_id(k,:)=strcmpi(con,curr_cond);
                end
                total_raw{N}{m}{i}=dt(:,curr_id(k,:));
                total_raw2{N}{m}{i}=dt2(:,curr_id(k,:));
                m=m+1;
            end
        end
    end
    
    %% Merge multiple blocks %%%%%%%%%%
    
    if numel(total_raw)>1
        for nn=1:Nt
            for cc=1:cn
                currcond = [];
                currcond2 = [];
                for jj=1:numel(total_raw)
                    currcond=[currcond total_raw{jj}{nn}{cc}];
                    currcond2=[currcond2 total_raw2{jj}{nn}{cc}];
                end
                total_plot{nn}{cc}=currcond;
                total_plot2{nn}{cc}=currcond2;
            end
        end
    else
        total_plot=total_raw{1};
        total_plot2=total_raw2{1};
    end
    beh_fp=total_plot;
    save(fullfile(D{1}.path,strcat('Epoched_HFB','.mat')),'evtfile','D','bch',...
        'beh_fp','labels','plot_cond','save_print','type','bc_type','total_plot2');
    signal_all=beh_fp;
end

win = window(51:950);
window = win;
t = t(window);
for j=1:length(labels)
    labels{j}(ismember(labels{j},'_'))=' ';
end
%% Run this when no GUI is needed
%Plot_script;

%% Run this to open a GUI and inspect the plots and images (electrodes)
sparam = 15;
page = 1;
yl= [-0.3 1.5];
if ~exist('total_plot2','var')
    total_plot2 = cell(1,length(evtfile));
end

if ~exist('bc_type','var')
    bc_type = 'z';
end
    plot_window(signal_all, sparam,labels,D,window,plot_cond, page, yl, bch, t, total_plot2, bc_type);
