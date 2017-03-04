#!/bin/bash
{
set -e
set -o pipefail

# Begin configuration
nbest=1
phnsyl=phn
nj=1
cmd=run.pl
stage=-1
# End configuration

echo "$0 $@"

. parse_options.sh
. ./path.sh
. ./g2p_path.sh

if [ $# -ne 3 ]; then
  echo "Usage: $0 <model-dir> <oov-list> <dir>";
  exit 1;
fi

# phonetisaurus may dump core if there are unseen sequences
ulimit -c 0

g2p_model_dir=$1
oov_list=$2
dir=$3

model=$g2p_model_dir/final.fst

if [ ! -f $model ]; then
  echo "Cannot find required file $model";
  exit 1
fi

[ -d $dir ] || mkdir -p $dir

if [ $stage -le -1 ]; then
# we need to remove '_' in graphemes because we also do that when building the model
sed -e 's#_##g' $oov_list > $dir/oov2predict.txt
paste $oov_list $dir/oov2predict.txt > $dir/oov_map
fi

if [ $stage -le 0 ]; then
echo "Predicting using phonetisaurus:"
if [ $nj -eq 1 ]; then
  cmd="phonetisaurus-g2pfst --return_on_unseen=true --model=$model --wordlist=$dir/oov2predict.txt \
    --nbest=$nbest > $dir/lexicon_raw.txt 2> $dir/g2p.err"

  echo "$cmd"
  eval $cmd
else
  [ -d $dir/split$nj ] || mkdir -p $dir/split$nj
  split_oov=""
  for n in $(seq $nj); do
    split_oov="$split_oov $dir/split$nj/oov2predict.$n.txt"
  done
  utils/split_scp.pl $dir/oov2predict.txt $split_oov
  $cmd JOB=1:$nj $dir/log/g2p.JOB.log \
    phonetisaurus-g2pfst --return_on_unseen=true --model=$model --wordlist=$dir/split$nj/oov2predict.JOB.txt \
    --nbest=$nbest \> $dir/split$nj/lexicon_raw.JOB.txt 2\> $dir/log/g2p.JOB.err
  
  for n in $(seq $nj); do
    cat $dir/split$nj/lexicon_raw.$n.txt
  done > $dir/lexicon_raw.txt
fi
fi

# Output is of the format
# word	0.867	phone1 phone2 phone3...

if [ $stage -le 1 ]; then
# Since we subsitute '|' and '}' when we build the model, we need to convert it back
# also since we map words to something without underscore, we need to map them back
awk -F'\t' '{gsub(/vbar/, "|", $3); gsub(/rbrk/, "}", $3); printf("%s\t%s\n", $1, $3);}' \
  $dir/lexicon_raw.txt | \
  awk -F'\t' 'NR==FNR {a[$2] = $1; next} {
    printf("%s\t%s\n", a[$1], $2);
  }' $dir/oov_map /dev/stdin > $dir/lexicon.tmp.txt

awk -v dir=$dir '{
  if (NF > 1) 
    print > dir"/lexicon_success.txt";
}' $dir/lexicon.tmp.txt

awk 'NR==FNR{a[$1]; next;}
     { if (!($1 in a)) print;
     }' $dir/lexicon_success.txt $oov_list > $dir/lexicon_failed.txt
fi

if [ $stage -le 2 ]; then
if [ $phnsyl == sylbound ]; then
  sed -e 's#\t\(= \)\+#\t#' -e 's#\( =\)\+#\t#g' -e 's#=$##' $dir/lexicon_success.txt | awk '{if (NF > 1) print}' > $dir/lexicon.txt
elif [ $phnsyl == syl ]; then
  sed -e 's# #\t #g' $dir/lexicon_success.txt | sed -e 's#=# #g' > $dir/lexicon.txt
elif [ $phnsyl == csyl ]; then
  echo "csyl: fixing syllable boundarys"
  g2p/g2p_onc2syl.pl $dir/lexicon_success.txt | sed -e 's#\t #\t#' > $dir/lexicon.txt
  exit
  if [ $nj == 1 ]; then
    g2p/get_syllable_boundaries.pl $dir/lexicon_success.txt \
      exp/g2p_nop_ngram7_csyl/phoneonc.syms exp/g2p_nop_ngram7_csyl/onc.syms \
      $g2p_model_dir/onc_boundary.fst $dir/phone > $dir/lexicon.txt
  else
    split_lex=""
    for n in $(seq $nj); do
      split_lex="$split_lex $dir/split$nj/lexicon.$n.txt"
    done
    utils/split_scp.pl $dir/lexicon_success.txt $split_lex
    $cmd JOB=1:$nj $dir/log/fix.JOB.log \
      g2p/get_syllable_boundaries.pl $dir/split$nj/lexicon.JOB.txt \
      $g2p_model_dir/phoneonc.syms $g2p_model_dir/onc.syms \
      $g2p_model_dir/onc_boundary.fst $dir/split$nj/phone.JOB \> $dir/split$nj/lexicon.fix.JOB.txt
  
    for n in $(seq $nj); do
      cat $dir/split$nj/lexicon.fix.$n.txt
    done > $dir/lexicon.txt

  fi
elif [ $phnsyl == phn2syl ]; then
  sed -e 's# #\t #g' -e 's#=# #g' $dir/lexicon_success.txt > $dir/lexicon.txt
else
  [ -f $dir/lexicon.txt ] && rm $dir/lexicon.txt
  (cd $dir; ln -s lexicon_success.txt lexicon.txt)
fi

fi

echo "$0: done!"
}
