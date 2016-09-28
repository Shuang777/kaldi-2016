// ivector3bin/ivector3-model-check-conditionAA

// Copyright 2016   Hang Su

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
#include "gmm/am-diag-gmm.h"
#include "ivector3/ivector-extractor.h"

int main(int argc, char *argv[]) {
  using namespace kaldi;
  using namespace kaldi::ivector3;
  typedef kaldi::int32 int32;
  typedef kaldi::int64 int64;
  try {
    const char *usage =
        "Check condition number of A^T*A\n"
        "Usage:  ivector3-model-check-conditionAA [options] <model-in> \n"
        " ivector3-model-check-conditionAA 1.ie \n";

    ParseOptions po(usage);
    
    po.Read(argc, argv);
    
    if (po.NumArgs() != 1) {
      po.PrintUsage();
      exit(1);
    }

    std::string model_rxfilename = po.GetArg(1);

    KALDI_LOG << "Reading model";
    IvectorExtractor extractor;
    ReadKaldiObject(model_rxfilename, &extractor);
    
    extractor.ComputeConditionNumberAA();
    
    KALDI_LOG << "Check condition number done." << endl;

    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
