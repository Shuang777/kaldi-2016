#!/usr/bin/perl

# Copyright 2014  International Computer Science Institute (author Hang Su)

$cmdline = join " ", $0, @ARGV;
print $cmdline . "\n";

$usetag = 1;
if ($ARGV[0] eq '--notag') {
  $usetag = 0;
  shift;
}


if ($#ARGV == 2) {
  $g2pLex = $ARGV[0];
  $refLex = $ARGV[1];
  $outDir = $ARGV[2];
} else {
  print STDERR ("Usage: $0 g2pLex realLex outDir\n");
  print STDERR (" e.g.: $0 oov_lex.txt lexiconp.wrd2syl.txt exp/gen_oov_lex");
  exit(1);
}

open (G2PLEX, $g2pLex) || die "Unable to open input g2pLex $g2pLex";
open (REFLEX, $refLex) || die "Unable to open input refLex $refLex";

while ($line = <REFLEX>) {
  chomp;
  if ($line =~ m:^([^\s]+)\s(.+)$:) {
    $w = $1;
    $pron = $2;
    $pron =~ s/{/lbrk/g;
    $pron =~ s/}/rbrk/g;
    $pron =~ s/\//slh/g;
    if ($usetag == 0) {
      $pron =~ s/_[0-9"]//g;
    }
    push (@{$prons{$w}}, $pron);
  } else {
    die "$0: cannot parse ref lex $refLex\nline: $line\n";
  }
}

mkdir($outDir) unless (-d $dir);

%g2p_prons = ();
while ($line = <G2PLEX>) {
  chomp;
  if ($line =~ m:^([^\s]+)\s(.+)$:) {
    $w = $1;
    $pron = $2;
    $pron =~ s/{/lbrk/g;
    $pron =~ s/}/rbrk/g;
    $pron =~ s/\//slh/g;
    if ($usetag == 0) {
      $pron =~ s/_[0-9"]+//g;
    }
    #if (exists $g2p_prons{$w}) {
      push(@{$g2p_prons{$w}}, $pron);
      #}
  } else {
    die "$0: cannot parse g2p lex $g2pLex\nline:$line\n";
  }
}

open (WORDID, "> $outDir/word_id.txt") || die "Unable to open output id file $outDir/word_id.txt";
open (G2PTRN, "> $outDir/hyp.trn") || die "Unable to open output trn file $outDir/hyp.trn";
open (REFTRN, "> $outDir/ref.trn") || die "Unable to open output trn file $outDir/ref.trn";
$count = 0;
foreach $w (keys %g2p_prons) {
  $uttid = "word_" . $count;
  print WORDID "$uttid $w\n";
  print G2PTRN "{ $g2p_prons{$w}[0]";
  for my $i (1..$#{$g2p_prons{$w}}) {
    print G2PTRN " / $g2p_prons{$w}[$i]";
  }
  print G2PTRN " } ($uttid)\n";
    
  print REFTRN "{ $prons{$w}[0]";
  for my $i (1..$#{$prons{$w}}) {
    print REFTRN " / $prons{$w}[$i]";
  }
  print REFTRN " } ($uttid)\n";
  $count += 1;
}

close(WORDID);
close(G2PTRN);
close(REFTRN);
