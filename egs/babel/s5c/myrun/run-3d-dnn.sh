#!/bin/bash
# This is written by Hang Su (ICSI)
# mostly copied from $KALDI_ROOT/egs/swbd/s5b/local/run_dnn.sh
# but made some changed to adapt to Babel data
{

set -e
set -o pipefail

echo "$0 $@"

# Begin configuration
stage=0
stage2=100
feattype=plp
cmd=./cmd.sh
semi=false
nnetfeattype=lda
flatstart=true
# End configuration

. ./path.sh
. parse_options.sh
. $cmd
. ./lang.conf

if [ $# -ne 0 ]; then
  echo "usage: $0 options "
  exit 1
fi

[ $feattype == plp ] && feattype=plp_pitch
traindata=train_$feattype

dbndir=exp/${traindata}_tri8_dbn
[ $semi == true ] && dbndir=${dbndir}_semi
[ $nnetfeattype == lda ] || dbndir=${dbndir}_$nnetfeattype
[ $flatstart == true ] || dbndir=${dbndir}_plpalign
if [ $stage -le 0 ]; then
if [ ! -f $dbndir/.done ]; then
  echo "-----------------------------------------------------------------"
  echo "Begin pretraining dbn in $dbndir on" `date`
  echo "-----------------------------------------------------------------"
  if [ $semi == true ]; then
    $cuda_cmd $dbndir/pretrain_dbn.log \
      mysteps/pretrain_dbn.sh --feat-type $nnetfeattype --transdir exp/${traindata}_tri5_ali --semidata data/unsup_pem_${feattype} --semitransdir exp/${traindata}_tri5/decode_unsup_pem_${feattype} data/${traindata} $dbndir
  elif [ $flatstart == true ]; then
    $cuda_cmd $dbndir/pretrain_dbn.log \
      mysteps/pretrain_dbn.sh --feat-type $nnetfeattype --transdir exp/${traindata}_tri5_ali data/${traindata} $dbndir
  else
    $cuda_cmd $dbndir/pretrain_dbn.log \
      mysteps/pretrain_dbn.sh --feat-type $nnetfeattype --transdir exp/${traindata}_tri5_plpalign_ali data/${traindata} $dbndir
  fi
  touch $dbndir/.done
fi
fi

dnndir=exp/${traindata}_tri8_dnn
[ $semi == true ] && dnndir=${dnndir}_semi
[ $nnetfeattype == lda ] || dnndir=${dnndir}_$nnetfeattype
[ $flatstart == true ] || dnndir=${dnndir}_plpalign
if [ $stage -le 1 ]; then
if [ ! -f $dnndir/.done ]; then
  echo "-----------------------------------------------------------------"
  echo "Begin training dnn in $dnndir on" `date`
  echo "-----------------------------------------------------------------"
  if [ $semi == true ]; then
    $cuda_cmd $dnndir/train_nnet.log \
    mysteps/train_nnet.sh --feat-type $nnetfeattype --feature-transform $dbndir/final.feature_transform --dbn $dbndir/6.dbn \
      --hid-layers 0 --learn-rate 0.008 --cv-subset-factor 0.1 --semidata data/unsup_pem_${feattype} \
      --semitransdir exp/${traindata}_tri5/decode_unsup_pem_${feattype} \
      --semialidir exp/${traindata}_tri6_nnet/decode_unsup_pem_${feattype} \
      data/${traindata} exp/${traindata}_tri5_ali $dnndir
  elif [ $flatstart == true ]; then
    $cuda_cmd $dnndir/train_nnet.log \
      mysteps/train_nnet.sh --feat-type $nnetfeattype --feature-transform $dbndir/final.feature_transform \
        --transdir exp/${traindata}_tri5_ali --dbn $dbndir/6.dbn --hid-layers 0 --learn-rate 0.008 \
        --cv-subset-factor 0.1 data/${traindata} exp/${traindata}_tri5_ali $dnndir
  else
    $cuda_cmd $dnndir/train_nnet.log \
      mysteps/train_nnet.sh --feat-type $nnetfeattype --feature-transform $dbndir/final.feature_transform \
        --transdir exp/${traindata}_tri5_plpalign_ali --dbn $dbndir/6.dbn --hid-layers 0 --learn-rate 0.008 \
        --cv-subset-factor 0.1 data/${traindata} exp/train_plp_pitch_tri5_ali $dnndir
  fi
  touch $dnndir/.done
fi
fi

exit;

alidir=${dnndir}_ali
if [ $stage -le 2 ]; then
if [ ! -f $alidir/.done ]; then
  echo "-----------------------------------------------------------------"
  echo "Begin aligning training data in $alidir on" `date`
  echo "-----------------------------------------------------------------"
  mysteps/align_nnet.sh --nj $train_nj --cmd "$train_cmd" --transform-dir exp/${traindata}_tri5_ali data/${traindata} $dnndir $alidir
  touch $alidir/.done
fi
fi

dnnredir=${dnndir}2
[ $semi == true ] && dnnredir=${dnnredir}_semi
if [ ! -f $dnnredir/.done ]; then
  echo "-----------------------------------------------------------------"
  echo "Begin training dnn in $dnnredir on" `date`
  echo "-----------------------------------------------------------------"
  if [ $semi == false ]; then
    #$cuda_cmd $dnnredir/train_nnet.log \
    #mysteps/train_nnet.sh --feature-transform $dbndir/final.feature_transform --dbn $dbndir/6.dbn --hid-layers 0 --learn-rate 0.008 --cv-subset-factor 0.1 data/${traindata} $alidir $dnnredir
    $cuda_cmd $dnnredir/train_nnet.log \
    mysteps/train_nnet.sh --feature-transform $dbndir/final.feature_transform --mlp-init $dnndir/final.nnet --hid-layers 0 --learn-rate 0.0008 --cv-subset-factor 0.1 data/${traindata} $alidir $dnnredir
  else
    mysteps/train_nnet.sh --feature-transform $dbndir/final.feature_transform --dbn $dbndir/6.dbn --hid-layers 0 --learn-rate 0.008 --cv-subset-factor 0.1 --semidata data/unsup_pem_${feattype} --semitransdir exp/${traindata}_tri5/decode_unsup_pem_${feattype} --semialidir $dnnredir/decode_unsup_pem_${feattype} --supcopy 3 data/${traindata} $aliredir $dnnredir
  fi
  touch $dnnredir/.done
fi

aliredir=${dnnredir}_ali
if [ ! -f $aliredir/.done ]; then
  echo "-----------------------------------------------------------------"
  echo "Begin aligning training data in $aliredir on" `date`
  echo "-----------------------------------------------------------------"
  mysteps/align_nnet.sh --nj $train_nj --cmd "$train_cmd" --transform-dir exp/${traindata}_tri5_ali data/${traindata} $dnnredir $aliredir
  touch $aliredir/.done
fi

exit 0;

denlatsdir=${dnndir}_denlats
if [ ! -f $denlatsdir/.done ]; then
  echo "-----------------------------------------------------------------"
  echo "Begin making denlats for training data in $denlatsdir on" `date`
  echo "-----------------------------------------------------------------"
  mysteps/make_denlats_nnet.sh --nj $train_nj --cmd "$train_cmd" --beam 13 --lattice-beam 8 --acwt 0.0833 --transform-dir exp/${traindata}_tri5_ali data/${traindata} exp/${traindata}_tri8_dnn $denlatsdir
  touch $denlatsdir/.done
fi

smbrdir=${dnndir}_smbr
if [ ! -f $smbrdir/.done ]; then
  echo "-----------------------------------------------------------------"
  echo "Begin smbr training on training data in $denlatsdir on" `date`
  echo "-----------------------------------------------------------------"
  mysteps/train_nnet_mpe.sh --cmd utils/run.pl --num-iters 1 --acwt 0.0833 --do-smbr true --scp_splits 20 --transform-dir exp/${traindata}_tri5_ali data/${traindata} $dnndir $alidir $denlatsdir $smbrdir
  touch $smbrdir/.done
fi

echo "-----------------------------------------------------------------"
echo "Training finished on" `date`
echo "-----------------------------------------------------------------"

exit 0;

mysteps/train_nnet_mmi.sh --cmd utils/run.pl --num-iters 1 --acwt 0.0833 --transform-dir exp/train_plp_pitch_tri5_ali data/train_plp_pitchexp/train_plp_pitch_tri8_dnn exp/train_plp_pitch_tri8_dnn_ali exp/train_plp_pitch_tri8_dnn_denlats exp/train_plp_pitch_tri8_dnn_mmi

}
