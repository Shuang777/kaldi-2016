#!/bin/bash
{
set -e
set -o pipefail

echo "$0 $@"

stage=-3
single=true
utt2utt=false

. ./cmd.sh
. ./path.sh
. ./conf/lang.conf
. parse_options.sh

passphrase=QgZc532G
langext=    # nothing or _nosp
#data=data_usabledev_uttnorm
data=data_usabledev
#data=data_usabledev_denoised8to16khz
wavdir=denoised_8to16khz_fix
cmvn_opts=''
#cmvn_opts='--norm-means=false'
nj=30
lmexts='t1 t1_swb t1_swb_fsh'
lmexts='t1_swb t1_swb_fsh'

if [ $stage -le -3 ]; then 
#local/cops_prepare_dict.sh
# we switch to cmudict now
local/cops_prepare_cmudict.sh $data

local/prep_data.sh --passphrase $passphrase --wavdir $wavdir --testset false /x/suhang/projects/cops/data $data $data/local/dict/lexicon.txt

utils/prepare_lang.sh $data/local/dict$langext "<unk>" $data/local/lang$langext $data/lang$langext

$single && exit
fi

# Now make MFCC features.
# mfccdir should be some place with a largish disk where you
# want to store MFCC features.
mfccdir=mfcc_$data

if [ $stage -le -2 ]; then
fisherdata=/u/drspeech/data/fisher/sentids/fsh-ldc+bbn.sentids
swbdata=/u/drspeech/data/tippi/users/suhang/ti/kaldi/try/swbd/data/train/text

local/train_lms.sh --fshdata $fisherdata --swbdata $swbdata \
  $data/train_nodev/text.usable $data/dev/text $data/local/dict$langext/lexicon.txt $data/local/lm

srilm_opts="-subset -unk -tolower -order 3"
LM=$data/local/lm/o3g.kn.gz
utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
    $data/lang$langext $LM $data/local/dict$langext/lexicon.txt $data/lang${langext}_t1

srilm_opts="-subset -prune-lowprobs -unk -tolower -order 3"
LM=$data/local/lm/swb_mix.3gram.kn.gz
utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
    $data/lang$langext $LM $data/local/dict$langext/lexicon.txt $data/lang${langext}_t1_swb

LM=$data/local/lm/lm.gz
utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
    $data/lang$langext $LM $data/local/dict$langext/lexicon.txt $data/lang${langext}_t1_swb_fsh

LM=$data/local/lm_0.5_0.5/swb_mix.3gram.kn.gz
utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
    $data/lang$langext $LM $data/local/dict$langext/lexicon.txt $data/lang${langext}_t1_swb_0.5

LM=$data/local/lm_0.5_0.5/fsh_mix.3gram.kn.gz
utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
    $data/lang$langext $LM $data/local/dict$langext/lexicon.txt $data/lang${langext}_t1_swb_fsh_0.5


$single && exit
fi


if $utt2utt && [ $stage -le -1 ]; then
for x in train_nodev dev test; do
  [ -d $data/$x ] || mkdir -p $data/$x
  cp data_usabledev/$x/{wav.scp,feats.scp,segments,text} $data/$x
  awk '{print $1,$1}' $data/$x/feats.scp > $data/$x/utt2spk
  utils/utt2spk_to_spk2utt.pl $data/$x/utt2spk > $data/$x/spk2utt
  steps/compute_cmvn_stats.sh $data/$x exp/${data}_make_mfcc/$x $mfccdir
  utils/fix_data_dir.sh $data/$x
done
(cd $data
[ -f lang ] || ln -s ../data_usabledev/lang
[ -f lang_t1 ] || ln -s ../data_usabledev/lang_t1
[ -f local ] || ln -s ../data_usabledev/local)

$single && exit
fi

if [ $stage -le 0 ]; then
for x in train_nodev dev test; do
  mysteps/make_mfcc.sh --passphrase $passphrase --nj $nj --cmd "$train_cmd" \
    $data/$x exp/${data}_make_mfcc/$x $mfccdir
  steps/compute_cmvn_stats.sh $data/$x exp/${data}_make_mfcc/$x $mfccdir
  utils/fix_data_dir.sh $data/$x
done

$single && exit
fi

[ "$cmvn_opts" == '--norm-means=false' ] && expext=_nocmvn

if [ $stage -le 1 ]; then
## Starting basic training on MFCC features
steps/train_mono.sh --nj $nj --cmd "$train_cmd" --cmvn_opts "$cmvn_opts" \
  $data/train_nodev $data/lang$langext exp/${data}_mono$expext

$single && exit
fi

if [ $stage -le 2 ]; then
steps/align_si.sh --nj $nj --cmd "$train_cmd" \
  $data/train_nodev data/lang$langext exp/${data}_mono$expext exp/${data}_mono_ali$expext

steps/train_deltas.sh --cmd "$train_cmd" --cmvn_opts "$cmvn_opts" \
  $numLeavesTri1 $numGaussTri1 $data/train_nodev $data/lang$langext exp/${data}_mono_ali$expext exp/${data}_tri1$expext

$single && exit
fi

if [ $stage -le 3 ];then
steps/align_si.sh --nj $nj --cmd "$train_cmd" \
  $data/train_nodev $data/lang$langext exp/${data}_tri1$expext exp/${data}_tri1_ali$expext

steps/train_deltas.sh --cmd "$train_cmd" --cmvn_opts "$cmvn_opts" \
  $numLeavesTri2 $numGaussTri2 $data/train_nodev $data/lang$langext exp/${data}_tri1_ali$expext exp/${data}_tri2$expext

$single && exit
fi

if [ $stage -le 4 ]; then 
# From now, we start using all of the data (except some duplicates of common
# utterances, which don't really contribute much).
steps/align_si.sh --nj $nj --cmd "$train_cmd" \
  $data/train_nodev $data/lang$langext exp/${data}_tri2$expext exp/${data}_tri2_ali_nodup$expext

# Do another iteration of LDA+MLLT training, on all the data.
steps/train_lda_mllt.sh --cmd "$train_cmd" --cmvn_opts "$cmvn_opts" \
  $numLeavesMLLT $numGaussMLLT $data/train_nodev $data/lang$langext exp/${data}_tri2_ali_nodup$expext exp/${data}_tri3$expext

$single && exit
fi

if [ $stage -le 5 ]; then
# Train tri4, which is LDA+MLLT+SAT, on all the (nodup) data.
steps/align_fmllr.sh --nj 30 --cmd "$train_cmd" \
  $data/train_nodev $data/lang${langext} exp/${data}_tri3$expext exp/${data}_tri3_ali_nodup$expext

steps/train_sat.sh --cmd "$train_cmd" \
  $numLeavesSAT $numGaussSAT $data/train_nodev $data/lang$langext \
  exp/${data}_tri3_ali_nodup$expext exp/${data}_tri4$expext

$single && exit
fi

nj_cv=30
if [ $stage -le 6 ]; then 
for lmext in $lmexts; do
  <<mono
  graph_dir=exp/${data}_mono/graph${langext}_$lmext
  utils/mkgraph.sh --mono $data/lang${langext}_$lmext \
    exp/${data}_mono$expext $graph_dir
  mysteps/decode.sh --utt-mode true --nj $nj_cv --cmd "$decode_cmd" $graph_dir \
    $data/dev exp/${data}_mono$expext/decode_dev${langext}_$lmext
mono

  <<tri1
  graph_dir=exp/${data}_tri1$expext/graph${langext}_$lmext
  $train_cmd $graph_dir/mkgraph.log \
    utils/mkgraph.sh $data/lang${langext}_$lmext exp/${data}_tri1$expext $graph_dir
  mysteps/decode_si.sh --utt-mode true --nj $nj_cv --cmd "$decode_cmd" --config conf/decode.config \
    $graph_dir $data/dev exp/${data}_tri1$expext/decode_dev${langext}_$lmext
tri1

  <<tri2
  graph_dir=exp/${data}_tri2/graph${langext}_$lmext
  $train_cmd $graph_dir/mkgraph.log \
    utils/mkgraph.sh $data/lang${langext}_$lmext exp/${data}_tri2$expext $graph_dir
  mysteps/decode.sh --utt-mode true --nj $nj_cv --cmd "$decode_cmd" --config conf/decode.config \
    $graph_dir $data/dev exp/${data}_tri2$expext/decode_dev${langext}_$lmext
tri2

  graph_dir=exp/${data}_tri3$expext/graph${langext}_$lmext
  $train_cmd -l mem_free=10G $graph_dir/mkgraph.log \
    utils/mkgraph.sh $data/lang${langext}_$lmext exp/${data}_tri3$expext $graph_dir
  mysteps/decode.sh --utt-mode true --nj $nj_cv --cmd "$decode_cmd" --config conf/decode.config \
    $graph_dir $data/dev exp/${data}_tri3$expext/decode_dev${langext}_$lmext &
  
#  mysteps/decode.sh --nj $nj --cmd "$decode_cmd" --config conf/decode.config \
#    $graph_dir $data/train_nodev exp/${data}_tri3$expext/decode_train_nodev${langext}_$lmext &
 
#  nj_tt=30
#  mysteps/decode.sh --nj $nj_tt --cmd "$decode_cmd" --config conf/decode.config \
#    $graph_dir data/test exp/tri3/decode_test${langext}_$lmext

  graph_dir=exp/${data}_tri4/graph${langext}_$lmext
  $train_cmd -l mem_free=10G $graph_dir/mkgraph.log \
    utils/mkgraph.sh $data/lang${langext}_$lmext exp/${data}_tri4$expext $graph_dir

  mysteps/decode_fmllr.sh --nj 30 --utt-mode true --cmd "$decode_cmd" \
    --config conf/decode.config \
    $graph_dir $data/dev exp/${data}_tri4$expext/decode_dev_$lmext &

  wait
done

$single && exit

fi

 
if [ $stage -le 7 ]; then
steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
  $data/train_nodev $data/lang$langext exp/${data}_tri4$expext exp/${data}_tri4_ali_nodup$expext
fi

feat_type=fmllr
alidir=exp/${data}_tri4_ali_nodup$expext
dbndir=exp/${data}_dnn5b_${feat_type}_dbn$expext
dnndir=exp/${data}_dnn5b_${feat_type}_dbn_dnn$expext
feature_transform=$dbndir/final.feature_transform
dbn=$dbndir/6.dbn

if [ $stage -le 8 ]; then
$cuda_cmd $dbndir/log/pretrain_dbn.log \
  mysteps/pretrain_dbn.sh --rbm-iter 1 --feat-type $feat_type \
  --transdir $alidir \
  $data/train_nodev $dbndir

$cuda_cmd $dnndir/log/train_nnet.log \
  mysteps/train_nnet.sh --feature-transform $feature_transform --dbn $dbn \
  --hid-layers 0 --learn-rate 0.008 \
  --resume-anneal false --feat-type $feat_type \
  $data/train_nodev $alidir $dnndir

$single && exit
fi

if [ $stage -le 9 ]; then

for lmext in $lmexts; do
  graph_dir=exp/${data}_tri4/graph${langext}_$lmext
  mysteps/decode_nnet.sh --utt-mode true --nj 30 --cmd "$decode_cmd -l mem_free=15G" \
    --config conf/decode_dnn.config --acwt 0.08333 --feat-type $feat_type \
    --transform-dir exp/${data}_tri4$expext/decode_dev_$lmext \
    $graph_dir $data/dev $dnndir/decode_dev_$lmext
done
$single && exit
fi

parallel_opts="-pe smp 16"
if [ $stage -le 10 ]; then
  steps/nnet2/train_pnorm_accel2.sh --parallel-opts "$parallel_opts" \
    --cmd "$train_cmd" --stage -10 \
    --num-threads 16 --minibatch-size 128 \
    --mix-up 20000 --samples-per-iter 300000 \
    --num-epochs 15 \
    --initial-effective-lrate 0.005 --final-effective-lrate 0.0002 \
    --num-jobs-initial 3 --num-jobs-final 10 --num-hidden-layers 5 \
    --pnorm-input-dim 5000  --pnorm-output-dim 500 $data/train_nodev \
    $data/lang$langext $alidir exp/${data}_nnet2_pnorm$expext
  
$single && exit
fi

if [ $stage -le 11 ]; then

for lmext in $lmexts; do
  graph_dir=exp/${data}_tri4/graph${langext}_$lmext
  mysteps/nnet2/decode.sh --utt-mode true --cmd "$decode_cmd" --nj 30 \
    --config conf/decode.config \
    --transform-dir exp/${data}_tri4$expext/decode_dev_$lmext \
    $graph_dir $data/dev \
    exp/${data}_nnet2_pnorm$expext/decode_dev_$lmext
done

$single && exit
fi

num_copies=5
frm=frm$num_copies
#frm=frm
shift_perturb=true

perturbed=full_perturbed
#perturbed=${frm}_perturbed

if [ $stage -le 12 ]; then
  if $shift_perturb ; then
    mysteps/get_shift_data.sh --num-copies $num_copies --passphrase $passphrase \
      --cmd "$train_cmd" --nj $nj --feature-type mfcc \
      conf/mfcc.conf $mfccdir exp/${perturbed}_mfcc_train_nodev \
      $data/train_nodev $data/train_${perturbed}_mfcc \
      $alidir ${alidir}_${perturbed}_made
  else 
    mysteps/nnet2/get_perturbed_feats.sh --num-copies 5 --passphrase $passphrase \
      --cmd "$train_cmd" --nj $nj --feature-type mfcc \
      conf/mfcc.conf $mfccdir exp/${perturbed}_mfcc_train_nodev \
      $data/train_nodev $data/train_${perturbed}_mfcc
  fi
  $single && exit
fi

if [ $stage -le 13 ]; then
alidir=exp/${data}_tri3_ali_${perturbed}$expext
# Train tri4, which is LDA+MLLT+SAT, on all the (nodup) data.
steps/align_fmllr.sh --nj 30 --cmd "$train_cmd" \
  $data/train_${perturbed}_mfcc $data/lang${langext} exp/${data}_tri3$expext $alidir

steps/train_sat.sh --cmd "$train_cmd" \
  $numLeavesSAT $numGaussSAT $data/train_${perturbed}_mfcc $data/lang$langext \
  $alidir exp/${data}_tri4_${perturbed}$expext

$single && exit
fi

if [ $stage -le 14 ]; then

for lmext in $lmexts; do
  (
  graph_dir=exp/${data}_tri4_${perturbed}$expext/graph${langext}_$lmext
  $train_cmd -l mem_free=10G $graph_dir/mkgraph.log \
    utils/mkgraph.sh $data/lang${langext}_$lmext exp/${data}_tri4_${perturbed}$expext $graph_dir

  mysteps/decode_fmllr.sh --nj $nj --utt-mode true --cmd "$decode_cmd" \
    --config conf/decode.config \
    $graph_dir $data/dev exp/${data}_tri4_${perturbed}$expext/decode_dev_$lmext )&
done
wait

$single && exit
fi

alidir=exp/${data}_tri4_ali_${perturbed}$expext
if [ $stage -le 15 ]; then

steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
  $data/train_${perturbed}_mfcc $data/lang$langext \
  exp/${data}_tri4_${perturbed}$expext $alidir

$single && exit

fi

if [ $stage -le 16 ]; then
dir=exp/${data}_nnet2_pnorm_${perturbed}$expext

mysteps/nnet2/train_pnorm_accel2.sh --parallel-opts "$parallel_opts" \
  --cmd "$train_cmd" --stage 60 \
  --num-threads 16 --minibatch-size 128 \
  --mix-up 20000 --samples-per-iter 300000 \
  --num-epochs 15 --skip-done true \
  --initial-effective-lrate 0.005 --final-effective-lrate 0.0002 \
  --num-jobs-initial 3 --num-jobs-final 10 --num-hidden-layers 5 \
  --pnorm-input-dim 5000  --pnorm-output-dim 500 $data/train_${perturbed}_mfcc \
  $data/lang$langext $alidir $dir

$single && exit
fi

if [ $stage -le 17 ]; then

for lmext in $lmexts; do
  graph_dir=exp/${data}_tri4_${perturbed}$expext/graph${langext}_$lmext
  mysteps/nnet2/decode.sh --utt-mode true --cmd "$decode_cmd" --nj 30 \
    --config conf/decode.config \
    --transform-dir exp/${data}_tri4_${perturbed}$expext/decode_dev_$lmext \
    $graph_dir $data/dev \
    exp/${data}_nnet2_pnorm_${perturbed}$expext/decode_dev_$lmext
done

$single && exit
fi

dbndir=exp/${data}_dnn5b_${feat_type}_dbn_${perturbed}$expext
dnndir=exp/${data}_dnn5b_${feat_type}_dbn_dnn_${perturbed}${expext}_spkcv

if [ $stage -le 18 ]; then
$cuda_cmd $dbndir/log/pretrain_dbn.log \
  mysteps/pretrain_dbn.sh --rbm-iter 1 --feat-type $feat_type \
  --transdir $alidir \
  $data/train_${perturbed}_mfcc $dbndir

$cuda_cmd $dnndir/log/train_nnet.log \
  mysteps/train_nnet.sh --feature-transform $feature_transform --dbn $dbn \
  --hid-layers 0 --learn-rate 0.008 --cv-base utt --min-iters 14\
  --resume-anneal false --feat-type $feat_type --cv-base spk \
  $data/train_${perturbed}_mfcc $alidir $dnndir

$single && exit
fi

if [ $stage -le 19 ]; then

for lmext in $lmexts; do
  graph_dir=exp/${data}_tri4_${perturbed}$expext/graph${langext}_$lmext
  mysteps/decode_nnet.sh --utt-mode true --nj 30 --cmd "$decode_cmd -l mem_free=15G" \
    --config conf/decode_dnn.config --acwt 0.08333 --feat-type $feat_type \
    --transform-dir exp/${data}_tri4_${perturbed}$expext/decode_dev_$lmext \
    $graph_dir $data/dev $dnndir/decode_dev_$lmext
done

$single && exit
fi

exit

steps/make_denlats.sh --nj 50 --cmd "$decode_cmd" \
  --config conf/decode.config --transform-dir exp/tri4_ali_nodup \
  data/train_nodup data/lang exp/tri4 exp/tri4_denlats_nodup

# 4 iterations of MMI seems to work well overall. The number of iterations is
# used as an explicit argument even though train_mmi.sh will use 4 iterations by
# default.
num_mmi_iters=4
steps/train_mmi.sh --cmd "$decode_cmd" \
  --boost 0.1 --num-iters $num_mmi_iters \
  data/train_nodup data/lang exp/tri4_{ali,denlats}_nodup exp/tri4_mmi_b0.1

for iter in 1 2 3 4; do
  (
    graph_dir=exp/tri4/graph_sw1_tg
    decode_dir=exp/tri4_mmi_b0.1/decode_eval2000_${iter}.mdl_sw1_tg
    steps/decode.sh --nj 30 --cmd "$decode_cmd" \
      --config conf/decode.config --iter $iter \
      --transform-dir exp/tri4/decode_eval2000_sw1_tg \
      $graph_dir data/eval2000 $decode_dir
  ) &
done
wait

if $has_fisher; then
  for iter in 1 2 3 4;do
    (
      steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
        data/lang_sw1_{tg,fsh_fg} data/eval2000 \
        exp/tri4_mmi_b0.1/decode_eval2000_${iter}.mdl_sw1_{tg,fsh_fg}
    ) &
  done
fi

# Now do fMMI+MMI training
steps/train_diag_ubm.sh --silence-weight 0.5 --nj 50 --cmd "$train_cmd" \
  700 data/train_nodup data/lang exp/tri4_ali_nodup exp/tri4_dubm

steps/train_mmi_fmmi.sh --learning-rate 0.005 \
  --boost 0.1 --cmd "$train_cmd" \
  data/train_nodup data/lang exp/tri4_ali_nodup exp/tri4_dubm \
  exp/tri4_denlats_nodup exp/tri4_fmmi_b0.1

for iter in 4 5 6 7 8; do
  (
    graph_dir=exp/tri4/graph_sw1_tg
    decode_dir=exp/tri4_fmmi_b0.1/decode_eval2000_it${iter}_sw1_tg
    steps/decode_fmmi.sh --nj 30 --cmd "$decode_cmd" --iter $iter \
      --transform-dir exp/tri4/decode_eval2000_sw1_tg \
      --config conf/decode.config $graph_dir data/eval2000 $decode_dir
  ) &
done
wait

if $has_fisher; then
  for iter in 4 5 6 7 8; do
    (
      steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" \
        data/lang_sw1_{tg,fsh_fg} data/eval2000 \
        exp/tri4_fmmi_b0.1/decode_eval2000_it${iter}_sw1_{tg,fsh_fg}
    ) &
  done
fi

# this will help find issues with the lexicon.
# steps/cleanup/debug_lexicon.sh --nj 300 --cmd "$train_cmd" data/train_nodev data/lang exp/tri4 data/local/dict/lexicon.txt exp/debug_lexicon

# SGMM system.
# local/run_sgmm2.sh $has_fisher

# Karel's DNN recipe on top of fMLLR features
# local/nnet/run_dnn.sh --has-fisher $has_fisher

# Dan's nnet recipe
# local/nnet2/run_nnet2.sh --has-fisher $has_fisher

# Dan's nnet recipe with online decoding.
# local/online/run_nnet2_ms.sh --has-fisher $has_fisher

# demonstration script for resegmentation.
# local/run_resegment.sh

# demonstration script for raw-fMLLR.  You should probably ignore this.
# local/run_raw_fmllr.sh

# nnet3 LSTM recipe
# local/nnet3/run_lstm.sh

# nnet3 BLSTM recipe
# local/nnet3/run_lstm.sh --affix bidirectional \
#	                  --lstm-delay " [-1,1] [-2,2] [-3,3] " \
#                         --label-delay 0 \
#                         --cell-dim 1024 \
#                         --recurrent-projection-dim 128 \
#                         --non-recurrent-projection-dim 128 \
#                         --chunk-left-context 40 \
#                         --chunk-right-context 40
}
