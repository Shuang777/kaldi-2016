// bin/copy-and-trim-int-vector.cc

// Copyright 2016 Hang Su

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
#include "transform/transform-common.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;

    const char *usage =
        "Copy and trim vectors of integers, according to feature length \n"
        "(e.g. alignments)\n"
        "\n"
        "Usage: copy-and-trim-int-vector [options] <length-in-rspecifier> <length-out-rspecifier> <utt-map> <vector-in-rspecifier> <vector-out-wspecifier>\n"
        " e.g.: copy-and-trim-int-vector \"ark:feat-to-len feats1.scp\" \"ark:feat-to-len feats2.scp\" ark:utt_map \"ark:gunzip -c ali.*.gz |\" \"ark:|gzip -c > ali.trim.gz\" ";
    
    bool trim_front = false;
    ParseOptions po(usage);

    po.Register("trim-front", &trim_front, "Trim int vector from front");

    po.Read(argc, argv);

    if (po.NumArgs() != 5) {
      po.PrintUsage();
      exit(1);
    }


    std::string length_in_rspecifier = po.GetArg(1),
        length_out_rspecifier = po.GetArg(2),
        uttmap_rspecifier = po.GetArg(3),
        int32vector_rspecifier = po.GetArg(4),
        int32vector_wspecifier = po.GetArg(5);

    RandomAccessInt32Reader length_in_reader(length_in_rspecifier);
    RandomAccessInt32Reader length_out_reader(length_out_rspecifier);
    RandomAccessTokenReader uttmap_reader(uttmap_rspecifier);
    SequentialInt32VectorReader vector_reader(int32vector_rspecifier);
    Int32VectorWriter vector_writer(int32vector_wspecifier);

    int32 num_done = 0, num_err = 0;
    for (; !vector_reader.Done(); vector_reader.Next()) {
      std::string utt = vector_reader.Key();
      if (!uttmap_reader.HasKey(utt)) {
        KALDI_WARN << "utterance " << utt << " not found in uttmap";
        num_err++;
        continue;
      }
      if (!length_in_reader.HasKey(utt)) {
        KALDI_WARN << "utterance " << utt << " not found in length-in-rspecifier";
        num_err++;
        continue;
      }
      std::string utt_out = uttmap_reader.Value(utt);
      std::vector<int32> vector_in = vector_reader.Value();

      int32 length_in = length_in_reader.Value(utt);
      int32 length_out = length_out_reader.Value(utt_out);

      KALDI_ASSERT(length_in == vector_in.size());

      if (length_out == length_in) {
        vector_writer.Write(utt_out, vector_in);
      } else if (length_out > length_in) {
        KALDI_ERR << "utterance " << utt << " length " << length_in 
          << " smaller than utterance " << utt_out << " (out) length " << length_out;
        num_err++;
        continue;
      } else {
        int32 to_trim = length_in - length_out;
        if (trim_front) {
          vector_in.erase(vector_in.begin(), vector_in.begin() + to_trim);
        } else {
          vector_in.erase(vector_in.end() - to_trim, vector_in.end());
        }
        vector_writer.Write(utt_out, vector_in);
      }
      num_done++;
    }
    KALDI_LOG << "Done " << num_done << " files, " << num_err << " with errors";

    return (num_done != 0 ? 0 : 1);

  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}


