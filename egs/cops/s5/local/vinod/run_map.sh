#!/bin/bash
{
set -e

#begin configuration
nbest=1
stage=0
single=true
#end configuration

echo "$0 $@"

. parse_options.sh

if [ $0 == "./run_map.sh" ]; then
  echo "Please call from folder above this level"
  exit 1
fi

#data=data_usabledev5
#expext=_middle  # _middle, _big
#perturb=_full_perturbed      # empty, full_perturbed
#dir=deliver_vinod/usabledev5_fix_re
#langext=_fix
#langext=_fix_swb_fsh
#dev=dev
#vinod=vinod

data=data_usable6
expext=_bigchn
expext=_bigchnswbdpert_sliding300
#expext=_sliding300
dir=deliver_vinod/version6
dev=dev_chn_concat
vinod=vinod_chn

langext=_fixall_swb_fsh

gmmdir=exp/${data}_tri4${perturb}$expext
dnndir=exp/${data}_dnn5b_fmllr_dbn_dnn${perturb}$expext

expext=_bigchnswbdpert2
dnnext=_peep_clip5_gpu2
gmmdir=exp/${data}_tri4${perturb}$expext
dnndir=exp/${data}_tfblstm_fmllr${perturb}${expext}$dnnext

if [ $stage -le 0 ]; then
awk 'NR==FNR {uttid = $2"-"$3; a[uttid]=$1; next} 
    { uttid = $1"-"$2; print a[uttid], $3, $4; }' $data/local/utt2uttid local/utt2id.vinod > $data/local/utt2id.vinod

[ -d $dir ] || mkdir -p $dir

lm_score=$(myutils/get_best_score.sh $gmmdir/decode_${dev}$langext)
echo best lm is $lm_score for $gmmdir/decode_${vinod}$langext

local/get_trans.sh --nbest $nbest --lm-score $lm_score \
  $gmmdir/decode_${vinod}$langext $gmmdir/graph$langext $dir/gmm${perturb}${expext}${langext}_${nbest}best.tra

python local/vinod/map2tsv.py --nbest $nbest --llk \
  $data/local/utt2id.vinod $dir/gmm${perturb}${expext}${langext}_${nbest}best.tra \
  $dir/gmm${perturb}${expext}${langext}_${nbest}best.tsv

lm_score=$(myutils/get_best_score.sh $dnndir/decode_${dev}$langext)

echo best lm is $lm_score for $dnndir/decode_${vinod}$langext

local/get_trans.sh --nbest $nbest --lm-score $lm_score \
  $dnndir/decode_${vinod}$langext $gmmdir/graph$langext \
  $dir/dnn${dnnext}${perturb}${expext}${langext}_${nbest}best.tra

python local/vinod/map2tsv.py --nbest $nbest --llk \
  $data/local/utt2id.vinod $dir/dnn${dnnext}${perturb}${expext}${langext}_${nbest}best.tra \
  $dir/dnn${dnnext}${perturb}${expext}${langext}_${nbest}best.tsv

$single && exit
fi

if [ $stage -le 1 ]; then
  . ./path.sh
  [ -d $dir/analysis ] || mkdir -p $dir/analysis
  lattice-oracle "ark:gunzip -c $dnndir/decode_${vinod}$langext/lat.*.gz |" \
    "ark:sym2int.pl -f 2- $gmmdir/graph$langext/words.txt <$data/${vinod}/text|" \
    ark,t:$dir/analysis/dnn${perturb}${expext}${langext}.oracle.tra \
    2>$dir/analysis/dnn${perturb}${expext}${langext}.oracle.log

$single && exit
fi

if [ $stage -le 2 ]; then
  nbestdir=$dir/analysis/dnn${perturb}${expext}_nbest
  [ -d $nbestdir ] || mkdir -p $nbestdir
  for i in `seq 10`; do
    awk -v i=$i '{
      pattern="-"i"$";
      if (match($1, pattern)){
        sub(pattern, "", $1);
        $2="";
        print
      }
    }' $dir/dnn${perturb}${expext}${langext}_10best.tra > $nbestdir/nbest$i.tra
  done

  for i in `seq 10`; do
    compute-wer --verbose=true --text --mode=present \
      ark:$data/$vinod/text ark:$nbestdir/nbest$i.tra \
      > $nbestdir/nbest$i.wer
    wers="$wers $nbestdir/nbest$i.wer"
  done
fi
 
if [ $stage -le 3 ]; then
  nbestdir=$dir/analysis/dnn${perturb}${expext}_nbest
  wers=""
  for i in `seq 10`; do
    wers="$wers $nbestdir/nbest$i.wer"
  done

  python3 local/vinod/summarize_wer.py $wers
fi

}
