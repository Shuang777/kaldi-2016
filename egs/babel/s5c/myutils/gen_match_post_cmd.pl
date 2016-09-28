#!/usr/bin/perl -w

$cmd = "filter-posts";
if ($ARGV[0] eq "-m") {
  shift @ARGV;
  $cmd = shift @ARGV;
}

if (@ARGV != 6) {
  die "Usage: $0 <src-dir> <src-nj> <dst-dir> <dst-nj> <src-post-dir> <dst-post-dir>\n"
}

$srcdir = $ARGV[0];
$srcnj = $ARGV[1];
$dstdir = $ARGV[2];
$dstnj = $ARGV[3];
$srcpostdir = $ARGV[4];
$dstpostdir = $ARGV[5];

for my $i (1..$dstnj) {
  my %utts = ();
  open(DSTF, "$dstdir/split$dstnj/$i/feats.scp") || die "Unable to open input $dstdir/split$dstnj/$i/feats.scp";
  while(<DSTF>) {
    my @A = split(/\s+/, $_);
    $utts{$A[0]} = 1;
  }
  my @matched = ();
  for my $j (1..$srcnj) {
    open(SRCF, "$srcdir/split$srcnj/$j/wav.scp") || die "Unable to open input $srcdir/split$srcnj/$j/wav.scp";
    while(<SRCF>) {
      my @A = split(/\s+/, $_);
      if (exists $utts{$A[0]}) {
        push @matched, $j;
        last;
      }
    }
    close(SRCF);
  }
  print "filter-posts \"ark:gunzip -c ";
  foreach my $j (@matched) {
    print "$srcpostdir/post.$j.gz ";
  }
  print "|\" ark:$dstdir/split$dstnj/$i/utt2spk \"ark:|gzip -c > $dstpostdir/post.$i.gz\"\n";
  close(DSTF);
}
