{

set -e
set -o pipefail

# Begin configuration
stage=0
nbest=2
nj=30
phnsyl=phn    # phn, syl, csyl, sylbound
posphone=false
usetag=true
# End configuration

. parse_options.sh

. ./lang.conf
. ./path.sh
. ./cmd.sh

if [ $# -ne 0 ]; then
  echo "Usage: $0"
  exit 1
fi

[ "$posphone" == "false" ] && langext=_nop
[ "$usetag" == "false" ] && langext=_not
[ "$posphone" == "false" ] && [ "$usetag" == "false" ] && langext=_nopnot

seq1_max=$(eval echo \$${phnsyl}_seq1_max)
seq2_max=$(eval echo \$${phnsyl}_seq2_max)
ngram_order_max=$(eval echo \$${phnsyl}_ngram_order_max)

if [ ! -f data/local${langext}/lexicon_full.txt ]; then
  langid=$(echo $langpack | perl -e 'while(<>) { $_ =~ /(\d\d+)/; print $1;}')
  echo langid is $langid
  if [ ! -f ../${langid}flp/data/local${langext}/lexicon.txt ]; then
    (cd ../${langid}flp; ./run-prep-lang.sh --posphone $posphone --usetag $usetag;)
  fi
  if [ ! -d data/local${langext} ]; then
    ./run-prep-lang.sh --posphone $posphone --usetag $usetag
  fi
  cp ../${langid}flp/data/local${langext}/lexicon.txt data/local${langext}/lexicon_full.txt
fi

awk 'NR==FNR {a[$1]; next} {if (!($1 in a)) print $1 }' \
  data/local${langext}/lexicon.txt data/local${langext}/lexicon_full.txt | \
  sort -u > data/local${langext}/flplex.oov.list

g2pdir=exp/g2p${langext}_ngram${ngram_order_max}_$phnsyl

if [ $stage -le 0 ]; then
  g2p/g2p_build_model_me.sh \
    --seq1-max $seq1_max --seq2-max $seq2_max \
    --ngram-order-max $ngram_order_max --phnsyl $phnsyl \
    data/local${langext}/lexicon.txt $g2pdir
fi

[ $nbest != 1 ] && nbestext=_nbest$nbest
oovdir=$g2pdir/gen_flpoov_lex${nbestext}

[ -d $oovdir ] || mkdir -p $oovdir

if [ $stage -le 1 ]; then
  g2p/g2p_get_prons_me.sh --cmd "$train_cmd" --nj $nj  \
    --nbest $nbest --phnsyl $phnsyl \
    $g2pdir data/local${langext}/flplex.oov.list $oovdir

  if [ $phnsyl == sylbound ] || [ $phnsyl == csyl ]; then
    if [ ! -f data/local${langext}/lexiconp.syl2phn.txt ]; then
      myutils/prepare_syl_lexicon.pl --posphone $posphone --usetag $usetag \
      data/local${langext} data/local${langext}/tmp.lang
    fi

    mylocal/map_oov_syl.sh --nj $nj $oovdir/lexicon.txt data/local${langext}/lexiconp.syl2phn.txt $oovdir
  fi

fi

if [ $stage -le 2 ]; then
  echo "Preparing trn files for scoring"
  myutils/gen_trn.pl $oovdir/lexicon.txt data/local${langext}/lexicon_full.txt $oovdir/phn
  myutils/gen_trn.pl --notag $oovdir/lexicon.txt data/local${langext}/lexicon_full.txt $oovdir/phn_notag

  if [ $phnsyl == syl ] || [ $phnsyl == sylbound ] || [ $phnsyl == csyl ] || [ $phnsyl == phn2syl ]; then
    sed -e 's# #=#g' -e 's#\t=# #g' -e 's#\t$##g' $oovdir/lexicon.txt > $oovdir/lexicon.syl.txt
    sed -e 's# #=#g' -e 's#\t=# #g' -e 's#\t$##g' data/local${langext}/lexicon_full.txt > $oovdir/lexicon_full.syl.txt
    myutils/gen_trn.pl $oovdir/lexicon.syl.txt $oovdir/lexicon_full.syl.txt $oovdir/$phnsyl
    myutils/gen_trn.pl --notag $oovdir/lexicon.syl.txt $oovdir/lexicon_full.syl.txt $oovdir/${phnsyl}_notag
  fi

  if [ $phnsyl == sylbound ] || [ $phnsyl == csyl ]; then
    sed -e 's# #=#g' -e 's#\t=# #g' -e 's#\t$##g' $oovdir/lexicon.mapped.txt > $oovdir/lexicon.mapped.syl.txt
    myutils/gen_trn.pl $oovdir/lexicon.mapped.syl.txt $oovdir/lexicon_full.syl.txt $oovdir/${phnsyl}map
    myutils/gen_trn.pl --notag $oovdir/lexicon.mapped.syl.txt $oovdir/lexicon_full.syl.txt $oovdir/${phnsyl}map_notag
  fi

fi

if [ $stage -le 3 ]; then
  mylocal/sclite_g2p.sh $oovdir/phn
  echo "phn oovdir $oovdir/phn"
  cat $oovdir/phn/sclite.sys

  mylocal/sclite_g2p.sh $oovdir/phn_notag
  echo "phn oovdir $oovdir/phn_notag"
  cat $oovdir/phn_notag/sclite.sys

  if [[ $phnsyl =~ syl ]]; then
    mylocal/sclite_g2p.sh $oovdir/$phnsyl
    echo "syl oovdir $oovdir/$phnsyl"
    cat $oovdir/$phnsyl/sclite.sys
    
    mylocal/sclite_g2p.sh $oovdir/${phnsyl}_notag
    echo "syl oovdir $oovdir/${phnsyl}_notag"
    cat $oovdir/${phnsyl}_notag/sclite.sys

    if [ $phnsyl == sylbound ] || [ $phnsyl == csyl ]; then
      mylocal/sclite_g2p.sh $oovdir/${phnsyl}map
      echo "syl map oovdir $oovdir/${phnsyl}map"
      cat $oovdir/${phnsyl}map/sclite.sys
      
      mylocal/sclite_g2p.sh $oovdir/${phnsyl}map_notag
      echo "syl map oovdir $oovdir/${phnsyl}map_notag"
      cat $oovdir/${phnsyl}map_notag/sclite.sys
    fi
  fi
fi

}
