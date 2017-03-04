// featbin/concat-feats.cc

// Copyright 2013 Johns Hopkins University (Author: Daniel Povey)
//           2015 Tom Ko

// See ../../COPYING for clarification regarding multiple authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
// WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
// MERCHANTABLITY OR NON-INFRINGEMENT.
// See the Apache 2 License for the specific language governing permissions and
// limitations under the License.


#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "matrix/kaldi-matrix.h"

namespace kaldi {

/*
   This function concatenates several sets of feature vectors
   to form a longer set. The length of the output will be equal
   to the sum of lengths of the inputs but the dimension will be
   the same to the inputs.
*/

void ConcatFeats(const std::vector<Matrix<BaseFloat> > &in,
                 Matrix<BaseFloat> *out) {
  KALDI_ASSERT(in.size() >= 1);
  int32 tot_len = in[0].NumRows(),
      dim = in[0].NumCols();
  for (int32 i = 1; i < in.size(); i++) {
    KALDI_ASSERT(in[i].NumCols() == dim);
    tot_len += in[i].NumRows();
  }
  out->Resize(tot_len, dim);
  int32 len_offset = 0;
  for (int32 i = 0; i < in.size(); i++) {
    int32 this_len = in[i].NumRows();
    out->Range(len_offset, this_len, 0, dim).CopyFromMat(
        in[i]);
    len_offset += this_len;
  }
}


}

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace std;

    const char *usage =
        "Stack features from the same speaker together\n"
        "Usage: concat-feats-spk <in-rxfilename1> <utt2spk> <out-wxfilename>\n"
        " e.g. concat-feats-spk scp:feats.scp data/utt2spk ark,scp:feats_spk.ark,feats_spk.scp\n"
        "See also: concat-feats\n";

    ParseOptions po(usage);

    po.Read(argc, argv);

    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }
    
    std::string feats_rspecifier = po.GetArg(1);
    std::string utt2spk_rspecifier = po.GetArg(2);
    std::string feats_wspecifier = po.GetArg(3);

    SequentialBaseFloatMatrixReader feature_reader(feats_rspecifier);
    RandomAccessTokenReader utt2spk_reader(utt2spk_rspecifier);
    BaseFloatMatrixWriter feature_writer(feats_wspecifier);

    int32 num_done = 0, num_err = 0;
    std::string last_spk = "";
    std::vector<Matrix<BaseFloat> > feats;
    Matrix<BaseFloat> output;
    for (; !feature_reader.Done(); feature_reader.Next()){
      std::string key = feature_reader.Key();
      const Matrix<BaseFloat> &mat = feature_reader.Value();
      if (!utt2spk_reader.HasKey(key)) {
        KALDI_WARN << "No spk info for utt " << key;
        num_err++;
        continue;
      }
      if (utt2spk_reader.Value(key) != last_spk && last_spk != "") {
        ConcatFeats(feats, &output);
        feature_writer.Write(last_spk, output);
        feats.resize(0);
        num_done++;
      }
      feats.push_back(mat);
      last_spk = utt2spk_reader.Value(key);
    }
    ConcatFeats(feats, &output);
    feature_writer.Write(last_spk, output);
    num_done++;

    KALDI_LOG << "Processed " << num_done << " utteranes, " 
              << num_err << " has error";

    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}

