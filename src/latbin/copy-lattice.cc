// latbin/copy-lattice.cc

// Copyright 2009-2011   Saarland University
// Author: Arnab Ghoshal

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
#include "fstext/fstext-lib.h"
#include "lat/kaldi-lattice.h"
#include "lat/lattice-functions.h"

int main(int argc, char *argv[]) {
  try {
    typedef kaldi::int32 int32;
    using fst::SymbolTable;
    using fst::VectorFst;
    using fst::StdArc;

    const char *usage =
        "Copy lattice.\n"
        "Usage: copy-lattice [options] lats-rspecifier lats-wspecifier\n"
        " e.g.: copy-lattice ark:1.lats ark:1.post\n";

    bool write_lattice = true;
    std::string until_lat = "";
    kaldi::ParseOptions po(usage);
    po.Register("write-lattice", &write_lattice, "write out lattice or not");
    po.Register("until-lat", &until_lat, "Copy until we met this lattice");
    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string lats_rspecifier = po.GetArg(1),
        lats_wspecifier = po.GetArg(2);

    // Read as regular lattice
    kaldi::SequentialLatticeReader lattice_reader(lats_rspecifier);
    kaldi::LatticeWriter lattice_writer(lats_wspecifier);

    int32 n_done = 0;

    for (; !lattice_reader.Done(); lattice_reader.Next()) {
      std::string key = lattice_reader.Key();
      kaldi::Lattice lat = lattice_reader.Value();
      // FreeCurrent() is an optimization that prevents the lattice from being
      // copied unnecessarily (OpenFst does copy-on-write).
      if (key == until_lat) {
        KALDI_LOG << "Lattice " << key << " met; Breaking loop.";
        break;
      }
      if (write_lattice) {
        lattice_writer.Write(key, lat);
      }

      KALDI_LOG << "Processed lattice for utterance: " << key;

      n_done++;
    }

    KALDI_LOG << "Done " << n_done << " lattices.";
    return (n_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
