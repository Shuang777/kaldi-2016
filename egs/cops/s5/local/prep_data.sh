#!/bin/bash

{
set -e
set -o pipefail

passphrase=
testset=true
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

transfile=$data/trans_modified_v3.json.gpg
[ ! -f "$transfile" ] && echo "Error: $transfile not found" && exit 1
[ ! -f "$lexicon" ] && echo "Error: $lexicon not found" && exit 1

echo "$passphrase" > PASSPHRASE.$$
cat PASSPHRASE.$$ | gpg --batch --passphrase-fd -0 -d $transfile | local/prep_data.py $local_dir
rm PASSPHRASE.$$

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

awk 'NR==FNR{chn2spk[$1]=$2; next;} {printf("%s_%s cat PASSPHRASE | gpg --batch --passphrase-fd 0 -d %s |\n"), chn2spk[$1], $1, $2}' $local_dir/chn2spk $local_dir/wav.flist > $local_dir/wav.scp

mv $local_dir/text $local_dir/text1

local/text_normalize.pl $local_dir/text1 > $local_dir/text2

local/map_words.pl $local_dir/text2 local/map.list $local_dir/text3

local/text_filter.pl local/map.list $lexicon $local_dir/text3 $local_dir/text $local_dir/oov

awk -v max_sec_per_word=2 'NR==FNR{a[$1]=$4-$3; next;} {if ((NF-1) * max_sec_per_word < a[$1]) print $0, " # sec: ", a[$1]}' $local_dir/segments $local_dir/text > $local_dir/too_long.list

awk '{for (i=2; i<=NF; i++) count[$i]+=1; } END{for (i in count) print i,count[i]}' $local_dir/text | sort -k2 -n -r > $local_dir/word.count

if $testset; then
  datas="train test"
else
  datas=train
fi

for i in $datas; do
  [ -d $dir/$i ] || mkdir $dir/$i
  cp $local_dir/{segments,text,utt2spk} $dir/$i
  awk -v i=$i 'NR==FNR{if ($2 == i) utts[$1]; next} {if ($1 in utts) print}' $local_dir/split $local_dir/wav.scp > $dir/$i/wav.scp
  utils/fix_data_dir.sh $dir/$i
  rm -r $dir/$i/.backup
done

[ -d $dir/dev ] && rm -rf $dir/dev
mkdir -p $dir/dev
for i in segments text wav.scp; do
  cp $dir/train/$i $dir/dev
done
[ ! -f local/dev.spk ] && echo "cannot find file local/dev.spk" && exit 1
awk 'NR==FNR{a[$1];next} {if ($1 in a) print}' local/dev.spk $dir/train/spk2utt > $dir/dev/spk2utt
utils/spk2utt_to_utt2spk.pl $dir/dev/spk2utt > $dir/dev/utt2spk
  
[ -d $dir/train_nodev ] && rm -rf $dir/train_nodev
mkdir -p $dir/train_nodev
for i in segments spk2utt text wav.scp; do
  cp $dir/train/$i $dir/train_nodev
done
awk 'NR==FNR{a[$1];next} {if (!($1 in a)) print}' local/dev.spk $dir/train/spk2utt > $dir/train_nodev/spk2utt
utils/spk2utt_to_utt2spk.pl $dir/train_nodev/spk2utt > $dir/train_nodev/utt2spk
utils/fix_data_dir.sh $dir/train_nodev

if $testset; then
  datas="dev test"
else
  datas=dev
fi

for x in $datas; do
  mv $dir/$x/segments $dir/$x/segments.bak
  awk 'NR==FNR{a[$1]=$2; next} {if (a[$1] == "True") print }' $local_dir/usable.txt $dir/$x/segments.bak > $dir/$x/segments
  utils/fix_data_dir.sh $dir/$x
done

awk 'NR==FNR{a[$1]=$2; next} {if (a[$1] == "True") print }' $local_dir/usable.txt $dir/train_nodev/text > $dir/train_nodev/text.usable

if $testset; then
  datas="dev test train_nodev"
else
  datas="dev train_nodev"
fi
for x in $datas; do
  awk '{print $2, $2, "A"}' $dir/$x/segments | sort -u > $dir/$x/reco2file_and_channel
  awk 'NR==FNR{ch[$1] = $2; st[$1] = $3; en[$1]=$4; next} {utt=$1; $1=""; print ch[utt], "A", ch[utt], st[utt], en[utt], "<O>", $0 }' $dir/$x/segments $dir/$x/text | cat local/stm.header - > $dir/$x/stm
done

[ -f local/glm ] && cp local/glm $dir/dev/glm
[ -f local/glm ] && cp local/glm $dir/test/glm

}
