#!/bin/bash

{
set -e
set -o pipefail

passphrase=

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

gpg --batch --yes --passphrase $passphrase -d $transfile | local/prep_data.py $local_dir

wavdir=$data/wav_16000hz

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

local/text_filter.pl $lexicon $local_dir/text2 $local_dir/text $local_dir/oov

for i in train test; do

  [ -d $dir/$i ] || mkdir $dir/$i

  cp $local_dir/{segments,text,utt2spk} $dir/$i

  awk -v i=$i 'NR==FNR{if ($2 == i) utts[$1]; next} {if ($1 in utts) print}' $local_dir/split $local_dir/wav.scp > $dir/$i/wav.scp
  
  utils/fix_data_dir.sh $dir/$i

  rm -r $dir/$i/.backup
done

[ -d $local_dir/train ] || mkdir $local_dir/train
cp local/sw-ms98-dict.text $local_dir/train

}
