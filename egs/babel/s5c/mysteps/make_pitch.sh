#!/bin/bash
{
set -e
set -o pipefail

# Copyright 2013 The Shenzhen Key Laboratory of Intelligent Media and Speech,
#                PKU-HKUST Shenzhen Hong Kong Institution (Author: Wei Shi)
#           2016  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0
# compute pitch features 

# Begin configuration section.
nj=4
cmd=run.pl
pitch_config=conf/pitch.conf
pitch_postprocess_config=
postprocess=true
paste_length_tolerance=2
compress=true
passphrase=
# End configuration section.

if ! [[ "$@" =~ passphrase ]]; then echo "$0 $@"; fi  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh

if [ $# -ne 3 ]; then
   echo "Usage: $0 [options] <data-dir> <log-dir> <pitch-dir> ]";
   echo "e.g.: $0 data/train exp/make_pitch/train mfcc"
   echo "Note: <log-dir> defaults to <data-dir>/log, and <pitch-dir> defaults to <data-dir>/data"
   echo "Options: "
   echo "  --pitch-config             <pitch-config-file>       # config passed to compute-kaldi-pitch-feats "
   echo "  --pitch-postprocess-config <postprocess-config-file> # config passed to process-kaldi-pitch-feats "
   echo "  --paste-length-tolerance   <tolerance>               # length tolerance passed to paste-feats"
   echo "  --nj                       <nj>                      # number of parallel jobs"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>)     # how to run jobs."
   exit 1;
fi

data=$1
logdir=$2
pitch_dir=$3

# make $pitch_dir an absolute pathname.
pitch_dir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $pitch_dir ${PWD}`

# use "name" as part of name of the archive.
name=`basename $data`

mkdir -p $pitch_dir
mkdir -p $logdir

if [ -f $data/feats.scp ]; then
  mkdir -p $data/.backup
  echo "$0: moving $data/feats.scp to $data/.backup"
  mv $data/feats.scp $data/.backup
fi

scp=$data/wav.scp

required="$scp $pitch_config"

for f in $required; do
  if [ ! -f $f ]; then
    echo "make_pitch.sh: no such file $f"
    exit 1;
  fi
done
utils/validate_data_dir.sh --no-text --no-feats $data || exit 1;

if [ ! -z "$pitch_postprocess_config" ]; then
	postprocess_config_opt="--config=$pitch_postprocess_config";
else
	postprocess_config_opt=
fi

if [ -f $data/spk2warp ]; then
  echo "$0 [info]: using VTLN warp factors from $data/spk2warp"
  vtln_opts="--vtln-map=ark:$data/spk2warp --utt2spk=ark:$data/utt2spk"
elif [ -f $data/utt2warp ]; then
  echo "$0 [info]: using VTLN warp factors from $data/utt2warp"
  vtln_opts="--vtln-map=ark:$data/utt2warp"
fi

for n in $(seq $nj); do
  # the next command does nothing unless $pitch_dir/storage/ exists, see
  # utils/create_data_link.pl for more info.
  utils/create_data_link.pl $pitch_dir/raw_pitch_$name.$n.ark
done


if [ -f $data/segments ]; then
  echo "$0 [info]: segments file exists: using that."
  split_segments=""
  for n in $(seq $nj); do
    split_segments="$split_segments $logdir/segments.$n"
  done

  utils/split_scp.pl $data/segments $split_segments || exit 1;
  [ -f $logdir/.error ] && rm $logdir/.error 2>/dev/null

  if $postprocess; then
    processcmds="process-kaldi-pitch-feats $postprocess_config_opt ark:- ark:- |"
  else
    processcmds=''
  fi

  if [ ! -z $passphrase ]; then
    touch PASSPHRASE.$$
    chmod 600 PASSPHRASE.$$
    echo $passphrase > PASSPHRASE.$$
    
    $cmd JOB=1:$nj $logdir/make_pitch_${name}.JOB.log \
      extract-segments "scp,p:sed 's#PASSPHRASE#PASSPHRASE.$$#' $scp |" $logdir/segments.JOB ark:- \| \
      compute-kaldi-pitch-feats --verbose=2 --config=$pitch_config ark:- ark:- \| $processcmds \
      copy-feats --compress=$compress ark:- \
        ark,scp:$pitch_dir/raw_pitch_$name.JOB.ark,$pitch_dir/raw_pitch_$name.JOB.scp

    rm PASSPHRASE.$$
  else
    pitch_feats="ark,s,cs:"

    $cmd JOB=1:$nj $logdir/make_pitch_${name}.JOB.log \
      extract-segments scp,p:$scp $logdir/segments.JOB ark:- \| \
      compute-kaldi-pitch-feats --verbose=2 --config=$pitch_config ark:- ark:- \| \
      process-kaldi-pitch-feats $postprocess_config_opt ark:- ark:- \| \
      copy-feats --compress=$compress ark:- \
        ark,scp:$pitch_dir/raw_pitch_$name.JOB.ark,$pitch_dir/raw_pitch_$name.JOB.scp
  fi

  rm $logdir/segments.*
else
  echo "$0: [info]: no segments file exists: assuming wav.scp indexed by utterance."
  split_scps=""
  for n in $(seq $nj); do
    split_scps="$split_scps $logdir/wav_${name}.$n.scp"
  done

  utils/split_scp.pl $scp $split_scps

  $cmd JOB=1:$nj $logdir/make_pitch_${name}.JOB.log \
    compute-kaldi-pitch-feats --verbose=2 --config=$pitch_config scp,p:$logdir/wav_${name}.JOB.scp ark:- \| \
    process-kaldi-pitch-feats $postprocess_config_opt ark:- ark:- \| \
    copy-feats --compress=$compress ark:- \
      ark,scp:$pitch_dir/raw_pitch_$name.JOB.ark,$pitch_dir/raw_pitch_$name.JOB.scp

  rm $logdir/wav_${name}.*.scp
fi


if [ -f $logdir/.error.$name ]; then
  echo "Error producing pitch features for $name:"
  tail $logdir/make_pitch_${name}.1.log
  exit 1;
fi

# concatenate the .scp files together.
for n in $(seq $nj); do
  cat $pitch_dir/raw_pitch_$name.$n.scp
done > $data/feats.scp


nf=`cat $data/feats.scp | wc -l`
nu=`cat $data/utt2spk | wc -l`
if [ $nf -ne $nu ]; then
  echo "It seems not all of the feature files were successfully processed ($nf != $nu);"
  echo "consider using utils/fix_data_dir.sh $data"
fi
if [ $nf -lt $[$nu - ($nu/20)] ]; then
  echo "Less than 95% the features were successfully generated.  Probably a serious error."
  exit 1;
fi

echo "Succeeded creating PLP & Pitch features for $name"
}
