#!/bin/bash
{
set -e
set -o pipefail

# this method perturb the data by shifting frame windows by a offset
echo "$0 $@"

# begin configuration section

cmd="run.pl"
num_copies=2  # support 2 or 4 perturbed copies of the data.
stage=0
nj=8
cleanup=true
feature_type=mfcc
passphrase=
# end configuration section

. utils/parse_options.sh 

if [ $# -ne 7 ]; then
  echo "Usage: $0 [options] <baseline-feature-config> <feature-storage-dir> <log-location> <input-data-dir> <output-data-dir> <input-ali-dir> <output-ali-dir>"
  echo "e.g.: $0 conf/fbank_40.conf mfcc exp/perturbed_fbank_train data/train data/train_perturbed_fbank exp/tri3_ali exp/tri3_ali_perturb"
  echo "Supported options: "
  echo "--feature-type (fbank|mfcc|plp)  # Type of features we are making, default fbank"
  echo "--cmd 'command-program'      # Mechanism to run jobs, e.g. run.pl"
  echo "--num-copies <n>             # Number of perturbed copies of the data (support 3, 4 or 5), default 5"
  echo "--stage <stage>              # Use for partial re-run"
  echo "--cleanup (true|false)       # If false, do not clean up temp files (default: true)"
  echo "--nj <num-jobs>              # How many jobs to use for feature extraction (default: 8)"
  exit 1;
fi

base_config=$1
featdir=$2
dir=$3 # dir/log* will contain log-files
inputdata=$4
data=$5
inputalidir=$6
alidir=$7

# Set pairs of (VTLN warp factor, time-warp factor)
# Aim to put these roughly in a circle centered at 1.0-1.0; the
# dynamic range of the VTLN warp factor will be 0.9 to 1.1 and
# of the time-warping factor will be 0.8 to 1.2.
if [ $num_copies -eq 2 ]; then
  shifts="2 -2" 
elif [ $num_copies -eq 4 ]; then
  shifts="2 4 -2 -4"
elif [ $num_copies -eq 5 ]; then
  shifts="1.6 3.3 5.0 -1.6 -3.3"
else
  echo "$0: unsupported --num-copies value: $num_copies (support 2 or 4)"
fi

for f in $base_config $inputdata/wav.scp; do 
  if [ ! -f $f ]; then
    echo "Expected file $f to exist"
    exit 1;
  fi
done

if [ "$feature_type" != "fbank" ] && [ "$feature_type" != "mfcc" ] && \
   [ "$feature_type" != "plp" ]; then 
  echo "$0: Invalid option --feature-type=$feature_type"
  exit 1;
fi

mkdir -p $featdir
mkdir -p $dir/conf $dir/log

all_feature_dirs=""

for fshift in $shifts; do
  conf=$dir/conf/$fshift.conf
  this_dir=$dir/$fshift
  
  if [ $(echo "$fshift < 0" | bc) -eq 1 ]; then
    real_shift=$(echo "$fshift+10" | bc)
  else
    real_shift=$fshift
  fi
  echo "real_shift is $real_shift"

  ( cat $base_config; echo; echo "--ms-offset=$real_shift";) > $conf
  
  echo "Making ${feature_type} features for miliseconds offset $fshift"

  feature_data=${data}-$fshift
  all_feature_dirs="$all_feature_dirs $feature_data"

  myutils/copy_data_dir.sh --utt-inter-prefix ${fshift}- $inputdata $feature_data
  mysteps/make_${feature_type}.sh --passphrase "$passphrase" --${feature_type}-config $conf --nj "$nj" --cmd "$cmd" $feature_data $this_dir $featdir

  steps/compute_cmvn_stats.sh $feature_data $this_dir $featdir
done

utils/combine_data.sh $data $all_feature_dirs $inputdata

ali_files=""
[ -d $alidir ] || mkdir -p $alidir
for fshift in $shifts; do
  shiftalidir=$alidir/shift$fshift
  [ -d $shiftalidir ] || mkdir -p $shiftalidir
  nj=`cat $inputalidir/num_jobs`
  feature_data=${data}-$fshift
  if [ $(echo "$fshift < 0" | bc) -eq 1 ]; then
    trim_front=true
  else
    trim_front=false
  fi

  copy-and-trim-int-vector --trim-front=$trim_front "ark:feat-to-len scp:$data/feats.scp ark:- |" "ark:feat-to-len scp:$feature_data/feats.scp ark:- |" ark:$feature_data/utt_map "ark:gunzip -c $inputalidir/ali.*.gz |" "ark:| gzip -c > $shiftalidir/ali.gz"

  ali_files="$ali_files $shiftalidir/ali.gz"
done

utils/split_data.sh $data $nj

$cmd JOB=1:$nj $alidir/log/filter.JOB.log \
  filter-int-vector "ark:gunzip -c $inputalidir/ali.*.gz $ali_files |" ark:$data/split$nj/JOB/utt2spk "ark:|gzip -c > $alidir/ali.JOB.gz"

copy-matrix "ark:cat $inputalidir/trans.* |" ark,scp:$alidir/trans,$alidir/trans.scp

$cmd JOB=1:$nj $alidir/log/filter_trans.JOB.log \
  utils/filter_scp.pl $data/split$nj/JOB/spk2utt $alidir/trans.scp \> $alidir/trans.JOB.scp \&\& \
  copy-matrix scp:$alidir/trans.JOB.scp ark:$alidir/trans.JOB

rm $alidir/{trans,trans.scp}
rm $alidir/trans.*.scp

for i in final.mdl full.mat num_jobs splice_opts cmvn_opts final.alimdl final.mat final.occs tree; do
  [ -f $inputalidir/$i ] && cp $inputalidir/$i $alidir
done

# In the combined feature directory, create a file utt2uniq which maps
# our extended utterance-ids to "unique utterances".  This enables the
# script steps/nnet2/get_egs.sh to hold out data in a more proper way.
cat $data/utt2spk | \
   perl -e ' while(<STDIN>){ @A=split; $x=shift @A; $y=$x; 
     foreach $fshift (@ARGV) { $y =~ s/^${fshift}-// && last; } print "$x $y\n"; } ' $shifts \
  > $data/utt2uniq

if $cleanup; then
  echo "$0: Cleaning up temporary directories for ${feature_type} features."
  # Note, this just removes the .scp files and so on, not the data which is located in
  # $featdir and which is still needed.
  rm -r $all_feature_dirs
fi
}
