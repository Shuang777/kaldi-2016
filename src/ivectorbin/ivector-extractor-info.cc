// ivectorbin/ivector-extractor-info.cc

// Copyright 2016  Hang Su

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
#include "gmm/full-gmm.h"
#include "ivector/ivector-extractor.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using kaldi::int32;

    const char *usage =
        "Initialize ivector-extractor\n"
        "Usage:  ivector-extractor-info [options] <ivector-extractor>\n"
        "e.g.:\n"
        " ivector-extractor-info 0.ie\n";

    IvectorExtractorOptions ivector_opts;
    ParseOptions po(usage);
    ivector_opts.Register(&po);

    po.Read(argc, argv);

    if (po.NumArgs() != 1) {
      po.PrintUsage();
      exit(1);
    }


    std::string ivector_extractor_rxfilename = po.GetArg(1);
        
    IvectorExtractor extractor;
    {
      bool binary_in;
      Input ki(ivector_extractor_rxfilename, &binary_in);
      extractor.Read(ki.Stream(), binary_in);
    }

    std::cout << extractor.Info();

    KALDI_LOG << "Info complete";

    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}

