// bin/interpolate-vector.cc

// Copyright 2016        Hang Su

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
#include "matrix/kaldi-vector.h"
#include "matrix/kaldi-matrix.h"

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;

    const char *usage =
        "Interpolate utterance based ivectors with speaker ivector\n"
        "\n"
        "Usage: interpolate-vector [options] <spk-ivector-rspecifier> <utt-ivector-rspecifier> <utt2spk-rspecifier> <interpolated-ivector-wspecifier>\n"
        " e.g.: interpolate-vector --weight=0.5 scp:spk_ivectors.scp scp:utt_ivectors.scp scp:data/train/utt2spk ark,scp:spk_utt_ivectors.ark,spk_utt_ivectors.scp\n";
      
    typedef kaldi::int32 int32;

    double weight = 0.5;
    std::string utt_length_rspecifier = "";
    int32 spk_length = 0;
    ParseOptions po(usage);

    po.Register("weight", &weight, "Interpolate with this weight placed on spk ivectors");
    po.Register("utt-length-rspecifier", &utt_length_rspecifier, "Length of each utterance");
    po.Register("spk-length", &spk_length, "Constant for each speaker, used for MAP adaptation");
    
    po.Read(argc, argv);

    if (po.NumArgs() != 4) {
      po.PrintUsage();
      exit(1);
    }


    std::string spk_ivector_rspecifier = po.GetArg(1),
        utt_ivector_rspecifier = po.GetArg(2),
        utt2spk_rspecifier = po.GetArg(3),
        ivector_wspecifier = po.GetArg(4);

    RandomAccessBaseFloatVectorReaderMapped spk_ivector_reader(spk_ivector_rspecifier, utt2spk_rspecifier);
    SequentialBaseFloatVectorReader utt_ivector_reader(utt_ivector_rspecifier);
    BaseFloatVectorWriter ivector_writer(ivector_wspecifier);

    RandomAccessInt32Reader utt_length_reader;
    if (utt_length_rspecifier != "") {
      utt_length_reader.Open(utt_length_rspecifier);
    }
    
    int32 num_done = 0;

    for (; !utt_ivector_reader.Done(); utt_ivector_reader.Next(), num_done++){
      std::string utt = utt_ivector_reader.Key();
      Vector<BaseFloat> utt_ivector = utt_ivector_reader.Value();
      Vector<BaseFloat> spk_ivector = spk_ivector_reader.Value(utt);

      if (utt_length_rspecifier != "") {
        weight = double (spk_length) / (utt_length_reader.Value(utt) + spk_length);
      }

      utt_ivector.Scale(1.0 - weight);
      utt_ivector.AddVec(weight, spk_ivector);
      ivector_writer.Write(utt, utt_ivector);
    }

    return (num_done != 0 ? 0 : 1);

  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}


