#!/bin/bash

{
set -e
set -o pipefail

passphrase=
wavdir=wav_16000hz

echo "$0 $@"

. ./path.sh
. parse_options.sh

if [ $# -ne 3 ]; then
  echo "Usage: $0 <path-to-data> <data-dir> <lexicon>"
  echo " e.g.: $0 /u/drspeech/xxx data data/local/dict_nosp/lexicon.txt"
  exit 1
fi

data=$1
dir=$2
lexicon=$3
local_dir=$dir/local

[ -d $dir ] || mkdir -p $dir
[ -d $local_dir ] || mkdir -p $local_dir

transfile=$data/trans_modified_v5.json.gpg
[ ! -f "$transfile" ] && echo "Error: $transfile not found" && exit 1
[ ! -f "$lexicon" ] && echo "Error: $lexicon not found" && exit 1

awk '{print $1}' local/utt2id.rob local/utt2id.vinod | sort -u > $local_dir/chn.rob_vinod

{
  echo "$passphrase" > PASSPHRASE.$$
  trap "rm PASSPHRASE.$$" EXIT
  cat PASSPHRASE.$$ | gpg --batch --passphrase-fd -0 -d $transfile | local/prep_data.py $local_dir/chn.rob_vinod $local_dir
}

wavdir=$data/$wavdir

if [ ! -d $wavdir ]; then
  echo "Error: $wavdir not found"
  exit 1;
fi

find $wavdir -iname '*.gpg' | sort > $local_dir/wav.list
sed -e 's?.*/??' -e 's?.AVI.*??' $local_dir/wav.list | paste - $local_dir/wav.list \
    > $local_dir/wav.flist

n=`cat $local_dir/wav.flist | wc -l`

[ $n -ne 2113 ] && echo "Warning: expected 2113 data files, found $n"

awk '{printf("%s cat PASSPHRASE | gpg --batch --passphrase-fd 0 -d %s |\n"), $1, $2}' $local_dir/wav.flist > $local_dir/wav.scp

mv $local_dir/text $local_dir/text1

local/text_normalize.pl $local_dir/text1 > $local_dir/text2

local/map_words.pl $local_dir/text2 local/map.list $local_dir/text3

local/text_filter.pl local/map.list $lexicon $local_dir/text3 $local_dir/text4 $local_dir/oov

perl -e 'while(<>) {
    ($first, $rest) = split(/\s/, $_, 2);
    chomp $rest;
    if ($rest eq "[noise]" ) {
      next;
    } else {
      print $_;
    }
  }' $local_dir/text4 > $local_dir/text

awk -v max_sec_per_word=2 'NR==FNR{a[$1]=$4-$3; next;} {if ((NF-1) * max_sec_per_word < a[$1]) print $0, " # sec: ", a[$1]}' $local_dir/segments $local_dir/text > $local_dir/rel_long.list
awk '{if ($4-$3 > 60) print $0, " # sec: ", $4-$3}' $local_dir/segments > $local_dir/too_long.list

awk '{for (i=2; i<=NF; i++) count[$i]+=1; } END{for (i in count) print i,count[i]}' $local_dir/text | sort -k2 -n -r > $local_dir/word.count

# we use wav.scp to track data split
for i in rob vinod; do
  awk '{print $1}' local/utt2id.$i | utils/filter_scp.pl - $local_dir/wav.scp > $local_dir/wav.$i
  awk 'NR==FNR {uttid = $2"-"$3; a[uttid]=$1; next} 
      { uttid = $1"-"$2; print a[uttid], $3, $4; }' \
      $data/local/utt2uttid local/utt2id.$i > $data/local/utt2id.$i
done

utils/filter_scp.pl --exclude $local_dir/wav.rob $local_dir/wav.scp | \
  utils/filter_scp.pl --exclude $local_dir/wav.vinod /dev/stdin > $local_dir/wav.left

utils/filter_scp.pl local/dev.stop_id $local_dir/wav.scp > $local_dir/wav.dev
utils/filter_scp.pl --exclude local/dev.stop_id $local_dir/wav.left > $local_dir/wav.train
cat $local_dir/wav.rob $local_dir/wav.vinod | sort -u > $local_dir/wav.test

for i in train train_spk dev dev_usable rob vinod test test_usable; do      # here we have train and test
  [ -d $dir/$i ] || mkdir $dir/$i
  cp $local_dir/{segments,text} $dir/$i
  if [ $i == train_spk ]; then
    cp $local_dir/utt2spk $dir/$i
  else
    cp $local_dir/utt2chn $dir/$i/utt2spk
  fi
  j=$i
  [[ $i =~ "train" ]] && j=train
  [[ $i =~ "dev" ]] && j=dev
  [[ $i =~ "test" ]] && j=test
  cp $local_dir/wav.$j $dir/$i/wav.scp
done

# we don't evaluate on utterances that only have "<unk>" or "[noise]"
for i in dev dev_usable test test_usable; do
  awk '{
    if (NF == 2) {
      if ($2 == "<unk>" || $2 == "[noise]" || $2 == "[laughter]") {
        next;
      }
    }
    print
  }' $local_dir/text > $dir/$i/text
done

for x in dev_usable test_usable; do
  mv $dir/$x/segments $dir/$x/segments.all
  awk 'NR==FNR{a[$1]=$2; next} {if (a[$1] == "True") print }' $local_dir/usable.txt $dir/$x/segments.all > $dir/$x/segments
done

for x in rob vinod; do
  mv $dir/$x/segments $dir/$x/segments.all
  awk 'NR==FNR{uttid=$2"-"$3; uttid2utt[uttid] = $1; next} {uttid=$1"-"$2; print uttid2utt[uttid]}' \
    $local_dir/utt2uttid local/utt2id.$x | \
    utils/filter_scp.pl /dev/stdin $dir/$x/segments.all > $dir/$x/segments
done

for x in train train_spk dev dev_usable test test_usable rob vinod; do
  utils/fix_data_dir.sh $dir/$x

  awk '{print $2, $2, "A"}' $dir/$x/segments | sort -u > $dir/$x/reco2file_and_channel
  awk 'NR==FNR{ch[$1] = $2; st[$1] = $3; en[$1]=$4; next} {utt=$1; $1=""; print ch[utt], "A", ch[utt], st[utt], en[utt], "<O>", $0 }' $dir/$x/segments $dir/$x/text | cat local/stm.header - > $dir/$x/stm
done

awk 'NR==FNR{a[$1]=$2; next} {if (a[$1] == "True") print }' $local_dir/usable.txt $dir/train/text > $dir/train/text.usable

awk 'NR==FNR{a[$1]; next} {if ($1 in a) print}' $local_dir/uttid_add $local_dir/text | cat $dir/train/text - > $dir/train/text.add

for i in dev test; do
  [ -f local/glm ] && cp local/glm $dir/$i/glm
done
}
