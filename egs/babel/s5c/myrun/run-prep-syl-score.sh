./run-prep-feat.sh --segmode seg --type dev10h


steps/align_fmllr.sh --boost-silence $boost_sil --nj $dev10h_nj --cmd "$decode_cmd" data/dev10h_seg_plp_pitch data/lang_nop exp/train_plp_pitch_tri5_nop exp/train_plp_pitch_tri5_ali_nop/dev10h_seg_plp_pitch

mylocal/wrd2syl_ali.sh --cmd myutils/custom.pl --posphone false data/local_nop/tmp.lang/lexiconp.txt data/local_nop/lexiconp.wrd2syl.txt data/lang_nop data/dev10h_seg_plp_pitch exp/train_plp_pitch_tri5_ali_nop/dev10h_seg_plp_pitch exp/train_plp_pitch_tri5_ali_nop/dev10h_seg_plp_pitch/syl_text

myutils/expand_stm.pl exp/train_plp_pitch_tri5_ali_nop/dev10h_seg_plp_pitch/syl_text/text data/local_nop/lexiconp.wrd2syl.txt data/dev10h/stm > data/dev10h/sylstm

cp data/dev10h/sylstm data/dev10h_uem_plp_pitch/sylstm

mylocal/score.sh --min-lmwt 8 --max-lmwt 20 --cmd myutils/slurm.pl --wrdsyl syl data/dev10h_uem_plp_pitch exp/train_plp_pitch_tri5_nop/graph_nop_syl exp/train_plp_pitch_tri6_nnet_nop/decode_dev10h_uem_plp_pitch_nop_syl


--- G2P

awk 'NR==FNR {a[$1];next;} {if (!($1 in a)) {print $1}}' data/local/lexiconp.txt /u/drspeech/data/swordfish/corpora/${langpack%*_LLP}/conversational/reference_materials/lexicon.txt > data/local_nop/flplex.oov.list

mylocal/gen_oov_lex.sh --nj 64 data/local_nop/flplex.oov.list $g2p_lex_fst exp/gen_flplex_oov_lex

[[ $lexiconFlags =~ '--romanized' ]] && sed -i -e 's#\t#\txxxxx\t#' -e 's#\-\([0-9]\)# _\1#g' exp/gen_flplex_oov_lex/oov_lexicon.raw.txt

mylocal/prepare_oov_lexicon.pl --phonemap "$phoneme_mapping" $lexiconFlags exp/gen_flplex_oov_lex/oov_lexicon.raw.txt exp/gen_flplex_oov_lex/

myutils/map_oov_syl.sh --nj 64 exp/gen_flplex_oov_lex/oov_lexicon.txt data/local_nop exp/map_flpoov_syl
perl -ape 's/(\S+\s+)(.+)/${1}1.0\t$2/;' < exp/map_flpoov_syl/lex.wrd2syl.txt > exp/map_flpoov_syl/lexp.wrd2syl.txt

mylocal/prepare_lexicon_ns.pl  --phonemap "$phoneme_mapping" $lexiconFlags /u/drspeech/data/swordfish/corpora/${langpack%*_LLP}/conversational/reference_materials/lexicon.txt data/local_full

perl -ape 's/(\S+\s+)(.+)/${1}1.0\t$2/;' < data/local_full/lexicon.txt > data/local_full/lexiconp.txt

myutils/prepare_syl_lexicon.pl data/local_full data/local_full/tmp.lang

sed -i 's#{#\|/#g' exp/map_flpoov_syl/lexp.wrd2syl.txt data/local_full/lexiconp.wrd2syl.txt

myutils/gen_trn.pl exp/map_flpoov_syl/lexp.wrd2syl.txt data/local_full/lexiconp.wrd2syl.txt exp/gen_trn

sclite -i rm -r exp/gen_trn/ref.trn trn -h exp/gen_trn/hyp.trn trn -s -f 0 -D -F -o sum rsum prf dtl sgml -e utf-8 -n sclite.syl

cat exp/gen_trn/ref.trn | tr '=' ' ' > exp/gen_trn/ref.phone.trn

cat exp/gen_trn/hyp.trn | tr '=' ' ' > exp/gen_trn/hyp.phone.trn

sclite -i rm -r exp/gen_trn/ref.phone.trn trn -h exp/gen_trn/hyp.phone.trn trn -s -f 0 -D -F -o sum rsum prf dtl sgml -e utf-8 -n sclite.phn


# new
trndir=exp/gen_trn_phone_novbar
myutils/gen_trn2.pl exp/gen_flplex_oov_lex_phone_novbar/oov_lexicon.raw.txt /u/drspeech/data/swordfish/corpora/${langp
ack%*_LLP}/conversational/reference_materials/lexicon.txt $trndir

sclite -i rm -r $trndir/ref.trn trn -h $trndir/hyp.trn trn -s -f 0 -D -F -o sum rsum prf dtl sgml -e utf-8 -n sclite.phn

