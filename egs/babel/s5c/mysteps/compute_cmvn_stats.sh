#!/bin/bash 

# Copyright 2012  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0
# To be run from .. (one directory up from here)
# see ../run.sh for example

# Compute cepstral mean and variance statistics per speaker.  
# We do this in just one job; it's fast.
# This script takes no options.
#
# Note: there is no option to do CMVN per utterance.  The idea is
# that if you did it per utterance it would not make sense to do
# per-speaker fMLLR on top of that (since you'd be doing fMLLR on
# top of different offsets).  Therefore what would be the use
# of the speaker information?  In this case you should probably
# make the speaker-ids identical to the utterance-ids.  The
# speaker information does not have to correspond to actual
# speakers, it's just the level you want to adapt at.
{
set -e
set -o pipefail

echo "$0 $@"  # Print the command line for logging

vad=false
fake=false
fake_dims=       # If specified, can generate 'fake' stats (that won't normalize)
                 # from a specified dimension.
two_channel=false

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh

if [ $# != 3 ]; then
   echo "Usage: $0 [options] <data-dir> <log-dir> <path-to-cmvn-dir>";
   echo "e.g.: $0 data/train exp/make_mfcc/train mfcc"
   echo "Options:"
   echo " --fake          gives you fake cmvn stats that do no normalization."
   echo " --two-channel   is for two-channel telephone data, there must be no segments "
   echo "                 file and reco2file_and_channel must be present.  It will take"
   echo "                 only frames that are louder than the other channel."
   echo " --fake-dims <n1:n2>  Generate stats that won't cause normalization for these"
   echo "                  dimensions (e.g. 13:14:15)"
   exit 1;
fi

data=$1
logdir=$2
cmvndir=$3

# make $cmvndir an absolute pathname.
cmvndir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $cmvndir ${PWD}`

# use "name" as part of name of the archive.
name=`basename $data`

mkdir -p $cmvndir || exit 1;
mkdir -p $logdir || exit 1;


required="$data/feats.scp $data/spk2utt"

for f in $required; do
  if [ ! -f $f ]; then
    echo "make_cmvn.sh: no such file $f"
    exit 1;
  fi
done

feats=scp:$data/feats.scp
if [ $vad == true ]; then
  feats="ark:select-voiced-frames $feats scp:$data/vad.scp ark:- |"
fi

if $fake; then
  dim=`feat-to-dim "$feats" -`
  cat $data/spk2utt | awk -v dim=$dim '{print $1, "["; for (n=0; n < dim; n++) { printf("0 "); } print "1";
                                                        for (n=0; n < dim; n++) { printf("1 "); } print "0 ]";}' | \
    copy-matrix ark:- ark,scp:$cmvndir/cmvn_$name.ark,$cmvndir/cmvn_$name.scp
elif $two_channel; then
  compute-cmvn-stats-two-channel $data/reco2file_and_channel "$feats" \
       ark,scp:$cmvndir/cmvn_$name.ark,$cmvndir/cmvn_$name.scp
elif [ ! -z "$fake_dims" ]; then
  compute-cmvn-stats --spk2utt=ark:$data/spk2utt "$feats" ark:- | \
    modify-cmvn-stats "$fake_dims" ark:- ark,scp:$cmvndir/cmvn_$name.ark,$cmvndir/cmvn_$name.scp
else
  compute-cmvn-stats --spk2utt=ark:$data/spk2utt "$feats" ark,scp:$cmvndir/cmvn_$name.ark,$cmvndir/cmvn_$name.scp
fi

cp $cmvndir/cmvn_$name.scp $data/cmvn.scp || exit 1;

nc=`cat $data/cmvn.scp | wc -l` 
nu=`cat $data/spk2utt | wc -l` 
if [ $nc -ne $nu ]; then
  echo "$0: warning: it seems not all of the speakers got cmvn stats ($nc != $nu);"
  [ $nc -eq 0 ] && exit 1;
fi

echo "Succeeded creating CMVN stats for $name"
}
