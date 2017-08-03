#!/bin/bash

grep Sum $1/score_*/*.sys | awk '{print $1, $(NF-2)}' | sed 's#.*score_\([0-9]*\).* \([0-9.]*\)*#\1 \2#' | sort -k2 -n | head -1 | awk '{print $1}'
