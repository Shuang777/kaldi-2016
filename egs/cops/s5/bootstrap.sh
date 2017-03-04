#!/bin/bash
{
set -e
set -o pipefail

stage=0
. parse_options.sh

dir=exp/data_bootstrap
[ -d $dir ] || mkdir -p $dir

decode=exp/data_tri3/decode_train_nodev_t1

if [ $stage -le 0 ]; then
  myutils/analyze_high_wer.sh $decode train_nodev $dir
fi

bootdir=data_bootstrap1/train_nodev
if [ $stage -le 1 ]; then
  echo "preparing $bootdir"
  [ -d $bootdir ] || mkdir -p $bootdir
  cp data/train_nodev/{cmvn.scp,reco2file_and_channel,segments,spk2utt,stm,text,utt2spk,wav.scp} $bootdir

  utils/filter_scp.pl --exclude $dir/utt2wer data/train_nodev/feats.scp > $bootdir/feats.scp

  utils/fix_data_dir.sh $bootdir

  awk 'NR==FNR{ch[$1] = $2; st[$1] = $3; en[$1]=$4; next} {utt=$1; $1=""; print ch[utt], "A", ch[utt], st[utt], en[utt], "<O,en>", $0 }' $bootdir/segments $bootdir/text > $bootdir/stm
fi

echo "bootstrap data prepared in $bootdir"
}
