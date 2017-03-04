#!/bin/bash
{

set -e

if [ $# -ne 1 ]; then 
  echo "Usage: $0 <dir>"
  exit 1
fi

dir=$1

for f in ref.trn hyp.trn word_id.txt; do
  if [ ! -f $dir/$f ]; then
    echo "cannot find required file $dir/$f"
    exit 1
  fi
done

echo "Performing sclite"
cmd="sclite -i rm -r $dir/ref.trn trn -h $dir/hyp.trn \
  trn -s -f 0 -D -F -o sum rsum prf dtl sgml -e utf-8 -n sclite"

echo "$cmd"
eval $cmd

awk 'NR==FNR {word2id[$1]=$2; next} {if ($1 == "id:") { gsub(/\(/, "", $2); gsub(/\)/, "", $2 ); $2 = word2id[$2]; }print }' $dir/word_id.txt $dir/sclite.prf > $dir/sclite.word.prf

}
