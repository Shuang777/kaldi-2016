#!/bin/bash
{
set -e
set -o pipefail

echo "$0 $@"

stage=-3
single=true
utt2utt=false
nj=30
nj_cv=30

. ./cmd.sh
. ./path.sh
. ./conf/lang_middle.conf

passphrase=QgZc532G
langext=    # nothing or _nosp
#data=data_usabledev_uttnorm
#data=data_usabledev8k
data=data_usabledev
data=data_usabledev5
#data=data_usabledev_denoised8to16khz
wavdir=wav_16000hz
#wavdir=wav_8000hz
#wavdir=denoised_8to16khz_fix
cmvn_opts=''
#cmvn_opts='--norm-means=false'
#config=conf/mfcc_8k.conf 
config=conf/mfcc.conf 
lmexts='t1 t1_swb t1_swb_fsh'
lmexts='t1 t1_swb_fsh'
#lmexts='t1_swb t1_swb_fsh'
lmexts='t1_swb_fsh'
#lmexts='t1'
#lmexts='fix fix_swb_fsh'
lmexts='fix_swb_fsh'
#lmexts='fixall fixall_swb_fsh'
#lmexts='fix'
decode_datas='dev vinod'
decode_datas='dev'
#decode_datas='dev_5'
#decode_datas='vinod_prateek2 vinod_prateek2_wpause'
decode_datas='dev_nospk'
decode_datas='vinod_prateek3 vinod_prateek3_wpause'
datas='train dev test'
skip_scoring=false

. parse_options.sh

if [ $stage -le -3 ]; then 
#local/cops_prepare_dict.sh
# we switch to cmudict now
#local/cops_prepare_cmudict.sh $data

local/prep_data.sh --passphrase $passphrase --wavdir $wavdir \
  /x/suhang/projects/cops/data $data $data/local/dict/lexicon.txt

exit

# filter lexicon
mv $data/local/dict/lexicon.txt $data/local/dict/lexicon_all.txt
awk 'NR==FNR{a[$1]; next} {if ($1 in a) print}' $data/local/word.count \
  $data/local/dict/lexicon_all.txt > $data/local/dict/lexicon.txt

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
  $data/train/text $data/dev/text $data/local/dict$langext/lexicon.txt $data/local/lm_fixall

lmext=_fixall

srilm_opts="-subset -unk -tolower -order 3"
LM=$data/local/lm$lmext/o3g.kn.gz
utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
    $data/lang$langext $LM $data/local/dict$langext/lexicon.txt $data/lang${langext}$lmext

srilm_opts="-subset -prune-lowprobs -unk -tolower -order 3"
LM=$data/local/lm$lmext/swb_mix.3gram.kn.gz
utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
    $data/lang$langext $LM $data/local/dict$langext/lexicon.txt $data/lang${langext}${lmext}_swb

LM=$data/local/lm$lmext/lm.gz
utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
    $data/lang$langext $LM $data/local/dict$langext/lexicon.txt $data/lang${langext}${lmext}_swb_fsh

#LM=$data/local/lm_0.5_0.5/swb_mix.3gram.kn.gz
#utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
#    $data/lang$langext $LM $data/local/dict$langext/lexicon.txt $data/lang${langext}_t1_swb_0.5

#LM=$data/local/lm_0.5_0.5/fsh_mix.3gram.kn.gz
#utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
#    $data/lang$langext $LM $data/local/dict$langext/lexicon.txt $data/lang${langext}_t1_swb_fsh_0.5

$single && exit
fi


if $utt2utt && [ $stage -le -1 ]; then
for x in train dev test; do
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
#for x in train dev test vinod rob; do
for x in $datas; do
  mysteps/make_mfcc.sh --mfcc-config $config --passphrase $passphrase --nj $nj --cmd "$train_cmd" \
    $data/$x exp/${data}_make_mfcc/$x $mfccdir
  steps/compute_cmvn_stats.sh $data/$x exp/${data}_make_mfcc/$x $mfccdir
  utils/fix_data_dir.sh $data/$x
done

$single && exit
fi

name=_nodev
expext=_nodev_big
name=_denoise
expext=_big_denoise
name=
expext=_big

[ "$cmvn_opts" == '--norm-means=false' ] && expext=_nocmvn

if [ $stage -le 1 ]; then
## Starting basic training on MFCC features
steps/train_mono.sh --nj $nj --cmd "$train_cmd" --cmvn_opts "$cmvn_opts" \
  $data/train${name} $data/lang$langext exp/${data}_mono$expext

$single && exit
fi

if [ $stage -le 2 ]; then
steps/align_si.sh --nj $nj --cmd "$train_cmd" \
  $data/train${name} $data/lang$langext exp/${data}_mono$expext exp/${data}_mono_ali$expext

steps/train_deltas.sh --cmd "$train_cmd" --cmvn_opts "$cmvn_opts" \
  $numLeavesTri1 $numGaussTri1 $data/train${name} $data/lang$langext exp/${data}_mono_ali$expext exp/${data}_tri1$expext

$single && exit
fi

if [ $stage -le 3 ];then
steps/align_si.sh --nj $nj --cmd "$train_cmd" \
  $data/train${name} $data/lang$langext exp/${data}_tri1$expext exp/${data}_tri1_ali$expext

steps/train_deltas.sh --cmd "$train_cmd" --cmvn_opts "$cmvn_opts" \
  $numLeavesTri2 $numGaussTri2 $data/train${name} $data/lang$langext exp/${data}_tri1_ali$expext exp/${data}_tri2$expext

$single && exit
fi

if [ $stage -le 4 ]; then 
# From now, we start using all of the data (except some duplicates of common
# utterances, which don't really contribute much).
steps/align_si.sh --nj $nj --cmd "$train_cmd" \
  $data/train${name} $data/lang$langext exp/${data}_tri2$expext exp/${data}_tri2_ali$expext

# Do another iteration of LDA+MLLT training, on all the data.
steps/train_lda_mllt.sh --cmd "$train_cmd" --cmvn_opts "$cmvn_opts" \
  $numLeavesMLLT $numGaussMLLT $data/train${name} $data/lang$langext exp/${data}_tri2_ali$expext exp/${data}_tri3$expext

$single && exit
fi

if [ $stage -le 5 ]; then
# Train tri4, which is LDA+MLLT+SAT, on all the (nodup) data.
steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
  $data/train${name} $data/lang${langext} exp/${data}_tri3$expext exp/${data}_tri3_ali$expext

steps/train_sat.sh --cmd "$train_cmd" \
  $numLeavesSAT $numGaussSAT $data/train${name} $data/lang$langext \
  exp/${data}_tri3_ali$expext exp/${data}_tri4$expext

$single && exit
fi

if [ $stage -le 6 ]; then 
for lmext in $lmexts; do
<<run
  graph_dir=exp/${data}_mono$expext/graph${langext}_$lmext
  utils/mkgraph.sh --mono $data/lang${langext}_$lmext \
    exp/${data}_mono$expext $graph_dir
  mysteps/decode.sh --utt-mode true --nj $nj_cv --cmd "$decode_cmd" $graph_dir \
    $data/dev exp/${data}_mono$expext/decode_dev${langext}_$lmext

  graph_dir=exp/${data}_tri1$expext/graph${langext}_$lmext
  $train_cmd -l mem_free=10G $graph_dir/mkgraph.log \
    utils/mkgraph.sh $data/lang${langext}_$lmext exp/${data}_tri1$expext $graph_dir
  mysteps/decode_si.sh --utt-mode true --nj $nj_cv --cmd "$decode_cmd" --config conf/decode.config \
    $graph_dir $data/dev exp/${data}_tri1$expext/decode_dev${langext}_$lmext

  graph_dir=exp/${data}_tri2/graph${langext}_$lmext
  $train_cmd -l mem_free=10G $graph_dir/mkgraph.log \
    utils/mkgraph.sh $data/lang${langext}_$lmext exp/${data}_tri2$expext $graph_dir
  mysteps/decode.sh --utt-mode true --nj $nj_cv --cmd "$decode_cmd" --config conf/decode.config \
    $graph_dir $data/dev exp/${data}_tri2$expext/decode_dev${langext}_$lmext
run

  graph_dir=exp/${data}_tri3$expext/graph${langext}_$lmext
  $train_cmd -l mem_free=10G $graph_dir/mkgraph.log \
    utils/mkgraph.sh $data/lang${langext}_$lmext exp/${data}_tri3$expext $graph_dir
  graph_dir=exp/${data}_tri3$expext/graph${langext}_$lmext
  for testdata in $decode_datas; do
    mysteps/decode.sh --utt-mode true --nj $nj_cv --cmd "$decode_cmd" --config conf/decode.config \
      $graph_dir $data/$testdata exp/${data}_tri3$expext/decode_${testdata}${langext}_$lmext &
  done

<<run
  graph_dir=exp/${data}_tri4$expext/graph${langext}_$lmext
  $train_cmd -l mem_free=10G $graph_dir/mkgraph.log \
    utils/mkgraph.sh $data/lang${langext}_$lmext exp/${data}_tri4$expext $graph_dir
  for testdata in $decode_datas; do
    mysteps/decode_fmllr.sh --stage 1 --utt-mode true --nj $nj_cv \
      --cmd "$decode_cmd" --config conf/decode.config --skip-scoring $skip_scoring \
      $graph_dir $data/$testdata exp/${data}_tri4$expext/decode_${testdata}${langext}_$lmext &
  done

  mysteps/decode.sh --nj $nj --cmd "$decode_cmd" --config conf/decode.config \
    $graph_dir $data/train${name} exp/${data}_tri3$expext/decode_train${name}${langext}_$lmext &
 
  nj_tt=30
  mysteps/decode.sh --nj $nj_tt --cmd "$decode_cmd" --config conf/decode.config \
    $graph_dir data/test exp/tri3/decode_test${langext}_$lmext
run

done
wait

$single && exit

fi

 
if [ $stage -le 7 ]; then
steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
  $data/train${name} $data/lang$langext exp/${data}_tri4$expext exp/${data}_tri4_ali$expext
fi

feat_type=fmllr
alidir=exp/${data}_tri4_ali$expext
dbndir=exp/${data}_dnn5b_${feat_type}_dbn$expext
dnndir=exp/${data}_dnn5b_${feat_type}_dbn_dnn$expext
feature_transform=$dbndir/final.feature_transform
dbn=$dbndir/6.dbn

if [ $stage -le 8 ]; then
$cuda_cmd $dbndir/log/pretrain_dbn.log \
  mysteps/pretrain_dbn.sh --rbm-iter 1 --feat-type $feat_type \
  --transdir $alidir \
  $data/train${name} $dbndir

$cuda_cmd $dnndir/log/train_nnet.log \
  mysteps/train_nnet.sh --feature-transform $feature_transform --dbn $dbn \
  --hid-layers 0 --learn-rate 0.008 \
  --resume-anneal false --feat-type $feat_type \
  $data/train${name} $alidir $dnndir

$single && exit
fi

if [ $stage -le 9 ]; then

for lmext in $lmexts; do
  for testdata in $decode_datas; do
    graph_dir=exp/${data}_tri4$expext/graph${langext}_$lmext
    mysteps/decode_nnet.sh --utt-mode true --nj $nj_cv --cmd "$decode_cmd -l mem_free=15G" \
      --config conf/decode_dnn.config --acwt 0.08333 --feat-type $feat_type --skip-scoring $skip_scoring \
      --transform-dir exp/${data}_tri4$expext/decode_${testdata}_$lmext \
      $graph_dir $data/$testdata $dnndir/decode_${testdata}_$lmext &
  done
  wait
done
$single && exit
fi

bndir=exp/nnet5b_bn1
if [ $stage -le 10 ]; then
  $cuda_cmd $bndir/log/train_nnet.log \
    mysteps/train_nnet.sh --hid-layers 2 --hid-dim 1024 --bn-dim 80 \
      --feat-type traps --splice 5 --traps-dct-basis 6 --learn-rate 0.008 \
    $data/train${name} $alidir $bndir
fi

bndir2=exp/nnet5b_bn2
if [ $stage -le 11 ]; then
  feature_transform=$bndir/final.feature_transform.part1
  nnet-concat $bndir/final.feature_transform \
    "nnet-copy --remove-last-layers=4 --binary=false $bndir/final.nnet - |" \
    "utils/nnet/gen_splice.py --fea-dim=80 --splice=2 --splice-step=5 |" \
    $feature_transform 
  
  # 2nd network, overall context +/-15 frames
  # - the topology will be 400_1500_1500_30_1500_NSTATES, again, the bottleneck is linear
  $cuda_cmd $bndir2/log/train_nnet.log \
    mysteps/train_nnet.sh --hid-layers 2 --hid-dim 1024 --bn-dim 30 \
      --feat-type traps --feature-transform $feature_transform --learn-rate 0.008 \
      $data/train${name} $alidir $bndir2
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
    --pnorm-input-dim 5000  --pnorm-output-dim 500 $data/train${name} \
    $data/lang$langext $alidir exp/${data}_nnet2_pnorm$expext
  
$single && exit
fi

if [ $stage -le 11 ]; then

for lmext in $lmexts; do
  graph_dir=exp/${data}_tri4/graph${langext}_$lmext
  mysteps/nnet2/decode.sh --utt-mode true --cmd "$decode_cmd" --nj $nj_cv \
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
shift_perturb=false

perturbed=full_perturbed
#perturbed=${frm}_perturbed

nj=20
if [ $stage -le 12 ]; then
  if $shift_perturb ; then
    mysteps/get_shift_data.sh --num-copies $num_copies --passphrase $passphrase \
      --cmd "$train_cmd" --nj $nj --feature-type mfcc \
      conf/mfcc.conf $mfccdir exp/${data}_${perturbed}_mfcc_train${name} \
      $data/train${name} $data/train_${perturbed}_mfcc \
      $alidir ${alidir}_${perturbed}_made
  else 
    mysteps/nnet2/get_perturbed_feats.sh --num-copies $num_copies --passphrase $passphrase \
      --cmd "$train_cmd" --nj $nj --feature-type mfcc \
      conf/mfcc.conf $mfccdir exp/${data}_${perturbed}_mfcc_train${name} \
      $data/train${name} $data/train_${perturbed}_mfcc
  fi
  $single && exit
fi

if [ $stage -le 13 ]; then
alidir=exp/${data}_tri3_ali_${perturbed}$expext
# Train tri4, which is LDA+MLLT+SAT, on all the (nodup) data.
#steps/align_fmllr.sh --nj $nj_cv --cmd "$train_cmd" \
#  $data/train_${perturbed}_mfcc $data/lang${langext} exp/${data}_tri3$expext $alidir

steps/train_sat.sh --cmd "$train_cmd" --stage 15\
  $numLeavesSAT $numGaussSAT $data/train_${perturbed}_mfcc $data/lang$langext \
  $alidir exp/${data}_tri4_${perturbed}$expext

$single && exit
fi

if [ $stage -le 14 ]; then

for lmext in $lmexts; do
  graph_dir=exp/${data}_tri4_${perturbed}$expext/graph${langext}_$lmext
  $train_cmd -l mem_free=10G $graph_dir/mkgraph.log \
    utils/mkgraph.sh $data/lang${langext}_$lmext exp/${data}_tri4_${perturbed}$expext $graph_dir

  for testdata in $decode_datas; do
    mysteps/decode_fmllr.sh --nj $nj_cv --utt-mode true --cmd "$decode_cmd" \
    --config conf/decode.config --skip-scoring $skip_scoring \
    $graph_dir $data/$testdata exp/${data}_tri4_${perturbed}$expext/decode_${testdata}_$lmext &
  done
  wait
done

$single && exit
fi

<<run
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
  mysteps/nnet2/decode.sh --utt-mode true --cmd "$decode_cmd" --nj $nj_cv \
    --config conf/decode.config \
    --transform-dir exp/${data}_tri4_${perturbed}$expext/decode_dev_$lmext \
    $graph_dir $data/dev \
    exp/${data}_nnet2_pnorm_${perturbed}$expext/decode_dev_$lmext
done

$single && exit
fi
run

dbndir=exp/${data}_dnn5b_${feat_type}_dbn_${perturbed}$expext
dnndir=exp/${data}_dnn5b_${feat_type}_dbn_dnn_${perturbed}${expext}

<<run
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
run

if [ $stage -le 19 ]; then

for lmext in $lmexts; do
  graph_dir=exp/${data}_tri4_${perturbed}$expext/graph${langext}_$lmext

  for testdata in $decode_datas; do
    mysteps/decode_nnet.sh --utt-mode true --nj $nj_cv --cmd "$decode_cmd -l mem_free=15G" \
      --config conf/decode_dnn.config --acwt 0.08333 --feat-type $feat_type \
      --scoring-opts "--min-lmwt 8 --max-lmwt 22" --skip-scoring $skip_scoring \
      --transform-dir exp/${data}_tri4_${perturbed}$expext/decode_${testdata}_$lmext \
      $graph_dir $data/$testdata $dnndir/decode_${testdata}_$lmext & 
  done
  wait
done

$single && exit
fi

#name=swbdn
#datadir=`pwd`/switchboard/renoise
#conf=conf/mfcc.conf
#name=swbdM
#datadir=`pwd`/switchboard/Mfiles
#conf=conf/mfcc_8k.conf
name=swbd_renoise16k
datadir=/u/drspeech/data/swordfish/users/suhang/data/LDC97S62
conf=conf/mfcc.conf


if [ $stage -le 20 ]; then
#  local/swbd1_data_prep.sh --regexp 's?M.wav??' $datadir data_usabledev $name
  local/swbd1_data_prep.sh --fileext '*.sph' --regexp 's?.sph??' $datadir $data $name

#  steps/make_mfcc.sh --mfcc-config $conf --nj $nj --cmd "$train_cmd" \
#    $data/$name exp/${data}_make_mfcc/$name $mfccdir
#  steps/compute_cmvn_stats.sh $data/$name exp/${data}_make_mfcc/$name $mfccdir 

#  utils/combine_data.sh $data/train_w$name $data/train${name} $data/$name
  $single && exit
fi

name=train_w$name
name=swbd_norm16k

if [ $stage -le 21 ]; then
  <<run
  # filter lexicon
  [ -d $data/local/dict_wswbd ] && rm -rf $data/local/dict_wswbd
  cp -r $data/local/dict $data/local/dict_wswbd
  cat $data/local/word.count $data/local/swbd/word.count | \
    awk 'NR==FNR{a[$1]; next} {if ($1 in a) print}' /dev/stdin \
    $data/local/dict_wswbd/lexicon_all.txt > $data/local/dict_wswbd/lexicon.txt
  rm $data/local/dict_wswbd/lexiconp.txt
run
  utils/prepare_lang.sh $data/local/dict_wswbd "<unk>" $data/local/lang_wswbd $data/lang_wswbd
  fisherdata=/u/drspeech/data/fisher/sentids/fsh-ldc+bbn.sentids
  swbdata=/u/drspeech/data/tippi/users/suhang/ti/kaldi/try/swbd/data/train/text

  local/train_lms.sh --fshdata $fisherdata --swbdata $swbdata \
    $data/train/text.usable $data/dev/text \
    $data/local/dict_wswbd/lexicon.txt $data/local_wswbd/lm
  
  exit

  LM=$data/local_wswbd/lm/lm.gz
  srilm_opts="-subset -unk -tolower -order 3"
#  utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
#    $data/lang_wswbd $LM $data/local/dict_wswbd/lexicon.txt \
#    $data/lang_wswbd_t1_swb_fsh

  prune-lm --threshold=1e-7 $LM /dev/stdout \
      | gzip -c > $data/local_wswbd/lm/sw1_fsh.o3g.pr1-7.kn.gz
  LM=$data/local_wswbd/lm/sw1_fsh.o3g.pr1-7.kn.gz
  utils/format_lm_sri.sh --srilm-opts "$srilm_opts" \
      $data/lang_wswbd $LM $data/local/dict_wswbd/lexicon.txt \
      $data/lang_wswbd_tgpr

  $single && exit
fi

if [ $stage -le 22 ]; then 
nj=100
<<run
steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
  $data/$name $data/lang_wswbd exp/${data}_tri3$expext exp/${data}_tri3_ali_${name}$expext

steps/train_sat.sh --cmd "$train_cmd" \
  $numLeavesSAT $numGaussSAT $data/$name $data/lang_wswbd \
  exp/${data}_tri3_ali_${name}$expext exp/${data}_tri4_${name}$expext

steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
  $data/$name $data/lang_wswbd exp/${data}_tri4$expext exp/${data}_tri4_ali_${name}$expext
run

dbndir=exp/${data}_dnn5b_${feat_type}_dbn${expext}
dnndir=exp/${data}_dnn5b_${feat_type}_dbn_dnn${expext}_swbd_norm16k

$cuda_cmd $dnndir/log/train_nnet.log \
  mysteps/train_nnet.sh --feature-transform $feature_transform --dbn $dbn \
  --hid-layers 0 --learn-rate 0.008 \
  --resume-anneal false --feat-type $feat_type \
  $data/$name exp/${data}_tri4_ali_${name}$expext $dnndir

dnninit=$dnndir/nnet/nnet_6.dbn_dnn_iter04_learnrate0.008_tr1.7217_cv2.1704
dnndir=exp/${data}_dnn5b_${feat_type}_dbn_dnn_swbdinit4_perturbed_spkcv
alidir=exp/${data}_tri4_ali_nodup$expext

#$cuda_cmd $dnndir/log/train_nnet.log \
#  mysteps/train_nnet.sh --feature-transform $feature_transform --mlp-init $dnninit \
#  --learn-rate 0.008 --resume-anneal false --feat-type $feat_type \
#  $data/train${name} $alidir $dnndir

for lmext in $lmexts; do
#  graph_dir=exp/${data}_tri4/graph${langext}_$lmext
#  trans_dir=exp/${data}_tri4/decode_dev_$lmext
  graph_dir=exp/${data}_tri4_full_perturbed/graph${langext}_$lmext
  trans_dir=exp/${data}_tri4_full_perturbed/decode_dev_$lmext
  mysteps/decode_nnet.sh --utt-mode true --nj $nj_cv --cmd "$decode_cmd -l mem_free=15G" \
    --config conf/decode_dnn.config --acwt 0.08333 --feat-type $feat_type \
    --transform-dir $trans_dir \
    $graph_dir $data/dev $dnndir/decode_dev_$lmext
done

$single && exit
fi

lmexts=wswbd_t1_swb_fsh
lmexts=wswbd_tgpr
if [ $stage -le 24 ]; then 
for lmext in $lmexts; do
  <<run
  graph_dir=exp/${data}_wswbd_mono/graph${langext}_$lmext
  utils/mkgraph.sh --mono $data/lang${langext}_$lmext \
    exp/${data}_wswbd_mono$expext $graph_dir
  mysteps/decode.sh --utt-mode true --nj $nj_cv --cmd "$decode_cmd" $graph_dir \
    $data/dev exp/${data}_wswbd_mono$expext/decode_dev${langext}_$lmext

  graph_dir=exp/${data}_wswbd_tri1$expext/graph${langext}_$lmext
  $train_cmd -l mem_free=10G $graph_dir/mkgraph.log \
    utils/mkgraph.sh $data/lang${langext}_$lmext exp/${data}_wswbd_tri1$expext $graph_dir
  mysteps/decode_si.sh --utt-mode true --nj $nj_cv --cmd "$decode_cmd" --config conf/decode.config \
    $graph_dir $data/dev exp/${data}_wswbd_tri1$expext/decode_dev${langext}_$lmext
run

  (
  graph_dir=exp/${data}_wswbd_tri2/graph${langext}_$lmext
  $train_cmd -l mem_free=10G $graph_dir/mkgraph.log \
    utils/mkgraph.sh $data/lang${langext}_$lmext exp/${data}_wswbd_tri2$expext $graph_dir
  mysteps/decode.sh --utt-mode true --nj $nj_cv --cmd "$decode_cmd -l mem_free=4G" --config conf/decode.config \
    $graph_dir $data/dev exp/${data}_wswbd_tri2$expext/decode_dev${langext}_$lmext 
  )&

  (
  graph_dir=exp/${data}_wswbd_tri3$expext/graph${langext}_$lmext
  $train_cmd -l mem_free=10G $graph_dir/mkgraph.log \
    utils/mkgraph.sh $data/lang${langext}_$lmext exp/${data}_wswbd_tri3$expext $graph_dir
  mysteps/decode.sh --utt-mode true --nj $nj_cv --cmd "$decode_cmd -l mem_free=4G" --config conf/decode.config \
    $graph_dir $data/dev exp/${data}_wswbd_tri3$expext/decode_dev${langext}_$lmext
  ) &
  
  (
  graph_dir=exp/${data}_wswbd_tri4/graph${langext}_$lmext
  $train_cmd -l mem_free=10G $graph_dir/mkgraph.log \
    utils/mkgraph.sh $data/lang${langext}_$lmext exp/${data}_wswbd_tri4$expext $graph_dir
  mysteps/decode_fmllr.sh --nj $nj_cv --utt-mode true --cmd "$decode_cmd -l mem_free=4G" \
    --config conf/decode.config \
    $graph_dir $data/dev exp/${data}_wswbd_tri4$expext/decode_dev_$lmext 
  ) &

  wait
done
fi

if [ $stage -le 25 ]; then
for x in train_nodev dev test; do
#for x in vinod rob; do
  utils/copy_data_dir.sh $data/$x $data/${x}_fbank
  mysteps/make_fbank.sh --passphrase $passphrase --nj $nj --cmd "$train_cmd" \
    $data/${x}_fbank exp/${data}_make_fbank/$x $mfccdir
  steps/compute_cmvn_stats.sh $data/${x}_fbank exp/${data}_make_fbank/$x $mfccdir
  utils/fix_data_dir.sh $data/${x}_fbank
done

$single && exit
fi

feat_type=traps

dbndir=exp/${data}_fbank_dbn
dnndir=exp/${data}_fbank_dbn_dnn
alidir=exp/${data}_tri4_ali_nodup$expext
name=_nodev

if [ $stage -le 26 ]; then
$cuda_cmd $dbndir/log/pretrain_dbn.log \
  mysteps/pretrain_dbn.sh --rbm-iter 1 --feat-type $feat_type \
  $data/train${name}_fbank $dbndir

$cuda_cmd $dnndir/log/train_nnet.log \
  mysteps/train_nnet.sh --feature-transform $feature_transform --dbn $dbn \
  --hid-layers 0 --learn-rate 0.008 \
  --resume-anneal false --feat-type $feat_type \
  $data/train${name}_fbank $alidir $dnndir
fi

lmexts='t1_swb_fsh'
if [ $stage -le 27 ]; then
for lmext in $lmexts; do
  for i in dev; do
    graph_dir=exp/${data}_tri4/graph${langext}_$lmext
    mysteps/decode_nnet.sh --utt-mode true --nj $nj_cv --cmd "$decode_cmd -l mem_free=15G" \
      --config conf/decode_dnn.config --acwt 0.08333 --feat-type $feat_type \
      $graph_dir $data/${i}_fbank $dnndir/decode_${i}_$lmext &
  done
  wait
done
fi

# Prateek's denoising

ext=_denoiseP

if [ $stage -le 28 ]; then
  for i in train_nodev vinod rob dev; do 
    [ -d $data/${i}$ext ] || mkdir -p $data/${i}$ext
    utils/copy_data_dir.sh $data/$i $data/${i}$ext
    cp arks_denoise/$i.scp $data/${i}$ext/feats.scp
    rm $data/${i}$ext/cmvn.scp
    steps/compute_cmvn_stats.sh $data/${i}$ext exp/${data}_make_mfcc/${i}$ext $mfccdir
  done
fi


exit

}
