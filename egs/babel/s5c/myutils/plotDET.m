function plotDET(trues_file, imposters_file)


path('/u/drspeech/data/tippi/users/suhang/ti/kaldi/try/sre08/DETware_v2.1', path);

trues = load(trues_file);
imposters = load(imposters_file);

[P_miss,P_fa] = Compute_DET(trues, imposters);
[eer,i] = min(abs(P_miss - P_fa));
eer = 0.5 * (P_miss(i) + P_fa(i));
f = figure('Visible','off');
Plot_DET(P_miss,P_fa,'k');
print('DET','-dpng');
