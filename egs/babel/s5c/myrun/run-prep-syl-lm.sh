## use _I in syl lex

cp data/local/{extra_questions.txt,nonsilence_phones.txt,optional_silence.txt,silence_phones.txt} data/local_syl2
mylocal/prepare_syl_lexicon.pl data/local/lexicon.txt data/local_syl2
(cd data/local_syl2; ln -s lexicon.syl2phn.txt lexicon.txt)

cat data/lang/phones/word_boundary.txt data/local_syl2/word_boundary.txt | sort -u > data/local_syl2/word_boundary.txt.new; mv data/local_syl2/word_boundary.txt.new data/local_syl2/word_boundary.txt

mkdir data/local_syl2/tmp.lang
myutils/prepare_lang.sh --position-dependent-phones false --share-silence-phones true data/local_syl2 $oovSymbol data/local_syl2/tmp.lang data/lang_syl2


mkdir data/lang_syl2/
cp data/lang_syl/G.fst data/lang_syl2/G.fst

myutils/slurm.pl -l mem_free=6G JOB=1:32 exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl2/log/convert.JOB.log lattice-align-words-lexicon data/lang/phones/align_lexicon.int? exp/train_plp_pitch_tri6_nnet/final.mdl "ark:gunzip -c exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl2/lat.JOB.gz |" ark,t:- \| utils/int2sym.pl -f 3 data/lang_syl2/words.txt.hescii \| myutils/convert_slf.pl - exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl2/convertlat
## end


mylocal/wali_to_syll_text.sh data/local/tmp.lang/lexiconp.txt data/local_syl/lexicon.wrd2syl.txt data/lang data/train_plp_pitch exp/train_plp_pitch_tri5_ali exp/train_plp_pitch_tri5_ali/syl_text

mylocal/wrd2syl.pl data/local_syl/lexicon.wrd2syl.txt < data/dev10h/text > data/dev10h/syl_text

local/train_lms_srilm.sh --words-file data/lang_syl/words.txt --train-text exp/train_plp_pitch_tri5_ali/syl_text/text --dev-text data/dev10h/syl_text data data/srilm_syl

# run decode

[ -d data/lang_test_syl ] || mkdir -p data/lang_test_syl
grep '<kwtext>' $dev10h_kwlist_file | cut -f2 -d'>' | cut -f1 -d'<' | tr ' ' '\n' | awk 'NR==FNR {a[$1]; next} !($1 in a)' data/local_syl/lexicon.wrd2syl.txt /dev/stdin > data/lang_syl/kw.oov.list

nj=32
split_oovs=""
for ((n=1; n<=nj; n++)); do
  split_oovs="$split_oovs `pwd`/data/lang_syl/oov.split/${n}.oov.list"
done

oovlist=`pwd`/data/lang_syl/kw.oov.list

utils/split_scp.pl $oovlist $split_oovs

splitoovlist=`pwd`/data/lang_syl/oov.split/JOB.oov.list

(
g2p_path=/u/drspeech/projects/swordfish/collab/phonetisaurus/v4b_chuck
cd $g2p_path
slurm.pl JOB=1:$nj /u/drspeech/data/swordfish/users/suhang/projects/swordfish/kaldi/kaldi-effort/exps/204llp/tmp/split.JOB.log ./g2p_get_prons.sh -m models/BABEL_OP1_204.syllable/lexicon.fst -v /u/drspeech/data/swordfish/users/suhang/projects/swordfish/kaldi/kaldi-effort/exps/204llp/data/lang_syl/oov.split/JOB.oov.list -S -h -o /u/drspeech/data/swordfish/users/suhang/projects/swordfish/kaldi/kaldi-effort/exps/204llp/data/lang_syl/oov.split/lex.JOB.oov.list

./g2p_get_prons.sh -m $g2p_path/models.dev/${langpack}.syllable/lexicon.fst -v $oovlist -S -h -o $(dirname $oovlist)/oov.lexicon.wrd2syl.txt.tmp
)

mkdir -p data/local_wrd2syl

cat data/lang_syl/oov.lexicon.wrd2syl.txt.tmp | sed -e 's#vbar#|#g' -e 's# # . #g' -e 's#=# #g' > data/lang_syl/oov.lexicon.wrd2syl.txt

[[ $lexiconFlags =~ '--romanized' ]] && sed -i -e 's#\t#\txxxxx\t#' data/lang_syl/oov.lexicon.wrd2syl.txt

cat $lexicon_file data/lang_syl/oov.lexicon.wrd2syl.txt > data/local_wrd2syl/lexicon_all.txt

local/prepare_lexicon.pl  --phonemap "$phoneme_mapping" $lexiconFlags data/local_wrd2syl/lexicon_all.txt data/local_wrd2syl

mylocal/prepare_syl_lexicon.pl data/local_wrd2syl/lexicon.txt data/local_wrd2syl

awk '{for (i=2; i <= NF; i++) {print $i}}' data/local_syl/lexicon.wrd2syl.txt | sort -u > seen.syl
awk 'NR==FNR {for (i=2; i <= NF; i++) {a[$i]} next;} {valid=1; for (i=2; i <= NF; i++) {if (!($i in a)) {print $i}} }' data/local_syl/lexicon.wrd2syl.txt data/local_wrd2syl/lexicon.wrd2syl.txt > unseen.syl

/u/fosler/research/iarpa/closesyls/closesyls.pl seen.syl unseen.syl > unseen.map

# awk 'NR==FNR {for (i=2; i <= NF; i++) {a[$i]} next;} {valid=1; for (i=2; i <= NF; i++) {if (!($i in a)) {valid=0}} if (valid == 1) {print}}' data/local_syl/lexicon.wrd2syl.txt data/local_wrd2syl/lexicon.wrd2syl.txt > data/local_wrd2syl/lexicon.wrd2syl.txt.filtered

awk 'NR==FNR {a[$1]=$2; next;} {for (i=2; i <= NF; i++) {if ($i in a) {$i=a[$i]}} print}' unseen.map data/local_wrd2syl/lexicon.wrd2syl.txt > data/local_wrd2syl/lexicon.wrd2syl.txt.mapped

awk '{$1=tolower($1); print}' data/local_wrd2syl/lexicon.wrd2syl.txt.mapped | sort > data/local_wrd2syl/lexicon.wrd2syl.txt.mapped.lower

mv data/local_wrd2syl/lexicon.wrd2syl.txt.mapped.lower data/local_wrd2syl/lexicon.wrd2syl.txt.mapped

# ndisambig=`utils/add_lex_disambig.pl data/local_wrd2syl/lexicon.wrd2syl.txt.filtered data/local_wrd2syl/lexicon_disambig.wrd2syl.txt.filtered`
ndisambig=`utils/add_lex_disambig.pl data/local_wrd2syl/lexicon.wrd2syl.txt.mapped data/local_wrd2syl/lexicon_disambig.wrd2syl.txt.mapped`
ndisambig=$[$ndisambig+1];

( for n in `seq 0 $ndisambig`; do echo '#'$n; done ) > data/local_wrd2syl/disambig.txt

mkdir -p data/lang_wrd2syl
# cat data/local_wrd2syl/lexicon.wrd2syl.txt.filtered | awk '{print $1}' | sort | uniq  | awk 'BEGIN{print "<eps> 0";} {printf("%s %d\n", $1, NR);} END{printf("#0 %d\n", NR+1);} ' > data/lang_wrd2syl/words.txt
cat data/local_wrd2syl/lexicon.wrd2syl.txt.mapped | awk '{print $1}' | sort | uniq  | awk 'BEGIN{print "<eps> 0";} {printf("%s %d\n", $1, NR);} END{printf("#0 %d\n", NR+1);} ' > data/lang_wrd2syl/words.txt

( for n in `seq 1 $ndisambig`; do echo '#'$n; done) | cat data/lang_syl/words.txt - | awk '{if (NF==1) print $1, (NR-1); else print;}' > data/lang_wrd2syl/syls.txt

utils/sym2int.pl data/lang_wrd2syl/syls.txt data/local_wrd2syl/disambig.txt > data/local_wrd2syl/disambig.int

# ./mylocal/arpa2G_syllables.sh data/srilm_boost/lm.gz data/lang_wrd2syl data/lang_wrd2syl

gunzip -c data/srilm_boost/lm.gz | \
  grep -v '<s> <s>' | grep -v '</s> <s>' |  grep -v '</s> </s>' | \
  arpa2fst - | \
  fstprint | \
  utils/eps2disambig.pl | \
  utils/s2eps.pl | \
  fstcompile --isymbols=data/lang_wrd2syl/words.txt \
  --osymbols=data/lang_wrd2syl/words.txt  --keep_isymbols=false --keep_osymbols=false | \
  fstrmepsilon > data/lang_wrd2syl/G.fst || exit 1
fstisstochastic data/lang_wrd2syl/G.fst

syl_disambig_symbol=`grep \#0 data/lang_wrd2syl/syls.txt | awk '{print $2}'`
word_disambig_symbol=`grep \#0 data/lang_wrd2syl/words.txt | awk '{print $2}'`
utils/make_lexicon_fst.pl data/local_wrd2syl/lexicon_disambig.wrd2syl.txt.mapped | fstcompile --isymbols=data/lang_wrd2syl/syls.txt --osymbols=data/lang_wrd2syl/words.txt --keep_isymbols=false --keep_osymbols=false | fstaddselfloops "echo $syl_disambig_symbol |" "echo $word_disambig_symbol |" | fstarcsort --sort_type=olabel > data/lang_wrd2syl/L_disambig.fst

## important LGdet.fst
fsttablecompose data/lang/L_disambig.wrd2syl.fst data/lang/G.boost.fst | fstdeterminizestar --use-log=true | fstrmsymbols data/lang/phones/disambig.wrd2syl.int | fstminimizeencoded > data/lang/LGdet.fst

myutils/slurm.pl -l mem_free=6G JOB=1:32 exp/train_plp_pitch_tri6_nnet_nop/decode_dev10h_uem_plp_pitch_nop_syl/log/syl2wrdG.JOB.log lattice-lmrescore --lm-scale=-1.0 "ark:gunzip -c exp/train_plp_pitch_tri6_nnet_nop/decode_dev10h_uem_plp_pitch_nop_syl/lat.1.gz |" "fstproject --project_output=true data/lang_nop/G.syl.fst |" ark:- \| lattice-compose ark:- data/lang_nop/LGdet.fst ark:- \| lattice-determinize ark:- ark:- \| lattice-align-words-lexicon data/lang_nop/phones/align_lexicon.wrd2syl.int exp/train_plp_pitch_tri6_nnet_nop/final.mdl ark:- "ark:| gzip -c > exp/train_plp_pitch_tri6_nnet_nop/decode_dev10h_uem_plp_pitch_nop_syl/wrdGlat.JOB.gz"

myutils/slurm.pl -l mem_free=10G JOB=1:32 exp/train_plp_pitch_tri6_nnet_nop/decode_dev10h_uem_plp_pitch_nop/log/wrdbak.JOB.log lattice-to-phone-lattice exp/train_plp_pitch_tri6_nnet_nop/final.mdl "ark:gunzip -c exp/train_plp_pitch_tri6_nnet_nop/decode_dev10h_uem_plp_pitch_nop/lat.JOB.gz |" ark:- \| lattice-compose ark:- data/lang_nop/Ldet.syl2phn.fst ark:- \| lattice-determinize ark:- ark:- \| lattice-align-words-lexicon data/lang_nop/phones/align_lexicon.syl2phn.int exp/train_plp_pitch_tri6_nnet_nop/final.mdl ark:- "ark:|gzip -c > exp/train_plp_pitch_tri6_nnet_nop/decode_dev10h_uem_plp_pitch_nop/syllat.JOB.gz" '&&' lattice-compose "ark:gunzip -c exp/train_plp_pitch_tri6_nnet_nop/decode_dev10h_uem_plp_pitch_nop/syllat.JOB.gz |" data/lang_nop/Ldet.wrd2syl.fst ark:- \| lattice-determinize ark:- ark:- \| lattice-align-words-lexicon data/lang_nop/phones/align_lexicon.wrd2syl.int exp/train_plp_pitch_tri6_nnet_nop/final.mdl "ark:| gzip -c > exp/train_plp_pitch_tri6_nnet_nop/decode_dev10h_uem_plp_pitch_nop/wrdbaklat.1.gz" 

## end important

# utils/make_lexicon_fst.pl data/local_wrd2syl/lexicon_disambig.wrd2syl.txt.filtered | \
utils/make_lexicon_fst.pl data/local_wrd2syl/lexicon_disambig.wrd2syl.txt.mapped | fstcompile --isymbols=data/lang_wrd2syl/syls.txt --osymbols=data/lang_wrd2syl/words.txt --keep_isymbols=false --keep_osymbols=false | fstdeterminizestar | fstrmsymbols data/local_wrd2syl/disambig.int | fstarcsort --sort_type=olabel > data/lang_wrd2syl/Ldet.fst

utils/make_lexicon_fst.pl data/local_wrd2syl/lexicon_disambig.wrd2syl.txt.mapped | fstcompile --isymbols=data/lang_wrd2syl/syls.txt --osymbols=data/lang_wrd2syl/words.txt --keep_isymbols=false --keep_osymbols=false | fstinvert | fstrmsymbols data/local_wrd2syl/disambig.int | fstarcsort --sort_type=olabel > data/lang_wrd2syl/Linv.fst

# myutils/custom.pl JOB=1:32 exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/log/alignsyl.JOB.log lattice-align-words data/lang_syl/phones/word_boundary.int exp/train_plp_pitch_tri6_nnet/final.mdl "ark:gunzip -c exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/syl.lat.JOB.gz |" "ark,t:| gzip -c > exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/alilat.JOB.gz"

## prepare align-lexicon
mkdir -p data/lang_wrd2syl/phones
cut -f 1 -d' ' --complement data/lang_syl/phones/align_lexicon.txt > data/lang_wrd2syl/phones/align_syl_lexicon.txt

#cat data/local_wrd2syl/lexicon.wrd2syl.txt.filtered | mylocal/prepare_wrd2phn_align.pl data/lang_wrd2syl/phones/align_syl_lexicon.txt > data/lang_wrd2syl/phones/align_wrd_lexicon.txt
cat data/local_wrd2syl/lexicon.wrd2syl.txt.mapped | mylocal/prepare_wrd2phn_align.pl data/lang_wrd2syl/phones/align_syl_lexicon.txt > data/lang_wrd2syl/phones/align_wrd_lexicon.txt

echo "<eps> SIL" >> data/lang_wrd2syl/phones/align_wrd_lexicon.txt

cat data/lang_wrd2syl/phones/align_wrd_lexicon.txt | \
 perl -ane '@A = split; print $A[0], " ", join(" ", @A), "\n";' | sort | uniq > data/lang_wrd2syl/phones/align_lexicon.txt

cat data/lang_wrd2syl/phones/align_lexicon.txt | utils/sym2int.pl -f 3- data/lang_syl/phones.txt | \
  utils/sym2int.pl -f 1-2 data/lang_wrd2syl/words.txt > data/lang_wrd2syl/phones/align_lexicon.int

myutils/hescii_words.py < data/lang_wrd2syl/words.txt > data/lang_wrd2syl/words.txt.hescii
## end

## prepare align-lexicon again
mkdir -p data/lang_wrd2syl/phones2
#cut -f 1 -d' ' --complement data/lang_syl2/phones/align_lexicon.txt > data/lang_wrd2syl/phones2/align_syl_lexicon.txt
#cat data/local_wrd2syl/lexicon.wrd2syl.txt.mapped | mylocal/prepare_wrd2phn_align.pl data/lang_wrd2syl/phones2/align_syl_lexicon.txt > data/lang_wrd2syl/phones2/align_wrd_lexicon.txt

cut -f 2 -d' ' --complement data/local_syl2/lexicon.pos.wrd2syl.txt > data/lang_wrd2syl/phones2/align_wrd_lexicon.txt
awk 'NR==FNR {a[$1]; next} 
     !($1 in a) {
         printf "%s",$1; 
         for (i=2; i<=NF; i++){
             n=split($i, prons, "=");
             if (n==1){
                 printf " %s_S",$i;
             } else {
                 if (i==2) {printf " %s_B", prons[1];}
                 else {printf " %s_I", prons[1];}
                 for (j=2; j<n; j++){
                     printf " %s_I",prons[j];
                 }
                 if (i==NF) {printf " %s_E", prons[n];}
                 else {printf " %s_I", prons[n];}
             }
         }
         printf "\n";
     }' data/lang_wrd2syl/phones2/align_wrd_lexicon.txt data/local_wrd2syl/lexicon.wrd2syl.txt.mapped >> data/lang_wrd2syl/phones2/align_wrd_lexicon.txt

echo "<eps> SIL" >> data/lang_wrd2syl/phones2/align_wrd_lexicon.txt

cat data/lang_wrd2syl/phones2/align_wrd_lexicon.txt | \
 perl -ane '@A = split; print $A[0], " ", join(" ", @A), "\n";' | sort | uniq > data/lang_wrd2syl/phones2/align_lexicon.txt

cat data/lang_wrd2syl/phones2/align_lexicon.txt | utils/sym2int.pl -f 3- data/lang_syl2/phones.txt | \
  utils/sym2int.pl -f 1-2 data/lang_wrd2syl/words.txt > data/lang_wrd2syl/phones2/align_lexicon.int
 
## end


phi=`grep -w '#0' data/lang_wrd2syl/words.txt | awk '{print $2}'`

myutils/hescii_words.py < data/lang/words.merge.txt > data/lang/words.merge.txt.hescii
mkdir -p exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/convertlat/
myutils/slurm.pl -l mem_free=6G JOB=1:32 exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/log/syl2wrd.JOB.log lattice-compose "ark:gunzip -c exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/lat.JOB.gz |" data/lang/Ldet.wrd2syl.fst ark:- \|  lattice-determinize ark:- ark:- \| lattice-align-words-lexicon data/lang/phones/align_lexicon.wrd2syl.int exp/train_plp_pitch_tri6_nnet/final.mdl ark:- ark,t:- \| utils/int2sym.pl -f 3 data/lang/words.merge.txt.hescii \| myutils/convert_slf.pl - exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/convertlat/


mkdir -p exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/convertlatG/
myutils/slurm.pl -l mem_free=6G JOB=1:32 exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_beam12_syl/log/syl2wrdG.JOB.log lattice-compose "ark:gunzip -c exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_beam12_syl/lat.JOB.gz |" data/lang/LGdet.fst ark:- \|  lattice-determinize ark:- ark:- \| lattice-align-words-lexicon data/lang/phones/align_lexicon.wrd2syl.int exp/train_plp_pitch_tri6_nnet/final.mdl ark:- ark,t:- \| utils/int2sym.pl -f 3 data/lang/words.merge.txt.hescii \| myutils/convert_slf.pl - exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_beam12_syl/convertlatG/


myutils/custom.pl -l mem_free=6G JOB=1:32 exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/log/syl2wrdLG.JOB.log lattice-compose "ark:gunzip -c exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/syl.lat.JOB.gz |" data/lang_wrd2syl/LGdet.fst ark:- \|  lattice-determinize ark:- ark:- \| lattice-align-words-lexicon data/lang_wrd2syl/phones/align_lexicon.int exp/train_plp_pitch_tri6_nnet/final.mdl ark:- ark,t:- \| utils/int2sym.pl -f 3 data/lang_wrd2syl/words.txt.hescii \| myutils/convert_slf.pl - exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/convertlatsylLG/

utils/make_lexicon_fst.pl --pron-probs data/local_syl/tmp.lang/lexiconp_disambig.txt 0.5 SIL | fstcompile --isymbols=data/lang_syl/phones.txt  --osymbols=data/lang_syl/words.txt --keep_isymbols=false --keep_osymbols=false | fstdeterminizestar | fstrmsymbols data/lang_syl/phones/disambig.int  | fstarcsort --sort_type=olabel > data/lang_syl/Ldet.fst

lattice-to-phone-lattice exp/train_plp_pitch_tri6_nnet/final.mdl "ark:gunzip -c exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch/lat.1.gz |" ark:- | lattice-compose ark:- data/lang_syl/Ldet.fst "ark:|gzip -c > exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/wrd2syl.lat.1.gz"

lattice-union "ark:gunzip -c exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/wrd2syl.lat.1.gz |" "ark:gunzip -c exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/syl.lat.1.gz |" "ark:|gzip -c > exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/syl.aug.lat.1.gz"

lattice-determinize "ark:gunzip -c exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/syl.aug.lat.1.gz |" "ark:|gzip -c > exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/syl.aug.det.lat.1.gz"


myutils/slurm.pl JOB=2:32 exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch_syl/log/wrdback.JOB.log \
  lattice-to-phone-lattice exp/train_plp_pitch_tri6_nnet/final.mdl "ark:gunzip -c exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch/lat.JOB.gz |" ark:- \| lattice-compose ark:- data/lang/Ldet.syl2phn.fst ark:- \| lattice-compose ark:- data/lang/Ldet.wrd2syl.fst "ark:| gzip -c > exp/train_plp_pitch_tri6_nnet/decode_dev10h_uem_plp_pitch/wrdbaklat.JOB.gz"


## try different syl lm
ngram-count -lm exp/train_plp_pitch_tri5_ali/syl_text/srilm/5gram.kn02223.gz -kndiscount1 -gt1min 0 -kndiscount2 -gt2min 2 -kndiscount3 -gt3min 2 -kndiscount4 -gt4min 2 -kndiscount5 -gt5min 3 -order 5 -text exp/train_plp_pitch_tri5_ali/syl_text/srilm/train.txt -vocab exp/train_plp_pitch_tri5_ali/syl_text/srilm/vocab -unk -sort

ngram-count -lm exp/train_plp_pitch_tri5_ali/syl_text/srilm/6gram.kn022223.gz -kndiscount1 -gt1min 0 -kndiscount2 -gt2min 2 -kndiscount3 -gt3min 2 -kndiscount4 -gt4min 2 -kndiscount5 -gt5min 2 -kndiscount6 -gt6min 3 -order 6 -text exp/train_plp_pitch_tri5_ali/syl_text/srilm/train.txt -vocab exp/train_plp_pitch_tri5_ali/syl_text/srilm/vocab -unk -sort

ngram-count -lm exp/train_plp_pitch_tri5_ali/syl_text/srilm/7gram.kn0222223.gz -kndiscount1 -gt1min 0 -kndiscount2 -gt2min 2 -kndiscount3 -gt3min 2 -kndiscount4 -gt4min 2 -kndiscount5 -gt5min 2 -kndiscount6 -gt6min 2 -kndiscount7 -gt7min 3 -order 7 -text exp/train_plp_pitch_tri5_ali/syl_text/srilm/train.txt -vocab exp/train_plp_pitch_tri5_ali/syl_text/srilm/vocab -unk -sort


ngram -order 5 -lm exp/train_plp_pitch_tri5_ali/syl_text/srilm/5gram.kn02223.gz -unk -ppl exp/train_plp_pitch_tri5_ali/syl_text/srilm/dev.txt  
file exp/train_plp_pitch_tri5_ali/syl_text/srilm/dev.txt: 10662 sentences, 157057 words, 0 OOVs
0 zeroprobs, logprob= -248849 ppl= 30.4596 ppl1= 38.4104


ngram -order 6 -lm exp/train_plp_pitch_tri5_ali/syl_text/srilm/6gram.kn022223.gz -unk -ppl exp/train_plp_pitch_tri5_ali/syl_text/srilm/dev.txt 
file exp/train_plp_pitch_tri5_ali/syl_text/srilm/dev.txt: 10662 sentences, 157057 words, 0 OOVs
0 zeroprobs, logprob= -249284 ppl= 30.6423 ppl1= 38.6564

ngram -order 7 -lm exp/train_plp_pitch_tri5_ali/syl_text/srilm/7gram.kn0222223.gz -unk -ppl exp/train_plp_pitch_tri5_ali/syl_text/srilm/dev.txt 
file exp/train_plp_pitch_tri5_ali/syl_text/srilm/dev.txt: 10662 sentences, 157057 words, 0 OOVs
0 zeroprobs, logprob= -249483 ppl= 30.726 ppl1= 38.7693



mylocal/arpa2G.sh --Gfst G5.syl.fst --words syls.txt exp/train_plp_pitch_tri5_ali/syl_text/srilm/5gram.kn02223.gz data/lang data/lang
mylocal/arpa2G.sh --Gfst G6.syl.fst --words syls.txt exp/train_plp_pitch_tri5_ali/syl_text/srilm/6gram.kn022223.gz data/lang data/lang
mylocal/arpa2G.sh --Gfst G7.syl.fst --words syls.txt exp/train_plp_pitch_tri5_ali/syl_text/srilm/7gram.kn0222223.gz data/lang data/lang



# new method

make_lexicon_fst_end.pl lexgraphs/lexicon_disambig.txt $silprob sil '#'$ndisambig |    fstcompile --isymbols=lexgraphs/phones_disambig.txt     --osymbols=lmgraphs/words_sil.txt     --keep_isymbols=false --keep_osymbols=false | fstdeterminizestar | fstrmsymbols lexgraphs/disambig.int | fstarcsort --sort_type=olabel     > Ldet.fst

lattice-copy ark:1.lat ark,t:- | myutils/lat_ali2time.pl | lattice-compose ark:- ~/Desktop/kaldi-graph-demo/Ldet.fst ark,t:- | utils/int2sym.pl -f 3 ~/Desktop/kaldi-graph-demo/lmgraphs/words_sil.txt | myutils/lattice-rmeps.pl - | myutils/convert_slf.pl --time-mode -

myutils/custom.pl JOB=1:32 exp/train_plp_pitch_tri6_nnet_nop/decode_dev10h_uem_plp_pitch_nop_syl/log/convertT.JOB.log lattice-copy "ark:gunzip -c exp/train_plp_pitch_tri6_nnet_nop/decode_dev10h_uem_plp_pitch_nop_syl/lat.JOB.gz |" ark,t:- \| sed -e 's#\t0\t#\t217\t#' \| myutils/lat_ali2time.pl \| lattice-compose ark:- data/lang_nop/Ldet.wrd2sylT.fst ark,t:- \| utils/int2sym.pl -f 3 data/lang_nop/words.merge.txt.hescii \| myutils/lattice-rmeps.pl - \| myutils/convert_slf.pl --time-mode - exp/train_plp_pitch_tri6_nnet_nop/decode_dev10h_uem_plp_pitch_nop_syl/convertlatT
