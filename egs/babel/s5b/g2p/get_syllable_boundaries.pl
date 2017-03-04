#!/usr/bin/perl
#

if ($#ARGV ne 4) {
  print STDERR "Usage: $0 <lexicon> <phoneoncsyms> <oncsyms> <onc_boundary_fst> <tmp-file-prefix>\n";
  exit(1);
}

$lexicon = $ARGV[0];
$phoneoncsyms = $ARGV[1];
$oncsyms = $ARGV[2];
$onc_boundary_fst = $ARGV[3];
$tmp_file_prefix = $ARGV[4];

open(LEXICON, "$lexicon") || die("Cannot open lexicon file $lexicon\n");
while($line = <LEXICON>) {
  ($word, $pron) = split(/\t/, $line);
  @phonesonc = split(/\s/, $pron);
  $pron_sylbound = &mark_syllable_boundary(\@phonesonc);
  print "$word\t$pron_sylbound\n";
}

exit(0);

sub mark_syllable_boundary{
  my $phonesonc = @{ $_[0] };
  my @phones;

  $cur = 0;
  open(PHONESTXT, "> $tmp_file_prefix.txt") || die("Failed to open $tmp_file_prefix.txt for writting\n");
  for(my $i = 0; $i <= $#phonesonc; $i++) {
    $next = $cur + 1;
    $phoneonc = $phonesonc[$i];
    ($phone, $onc) = split(/\//, $phoneonc);
    print PHONESTXT "$cur $next $phoneonc $onc\n";
    $cur = $next;
  }
  print PHONESTXT "$cur\n";
  close(PHONESTXT);

  system("fstcompile --isymbols=$phoneoncsyms --osymbols=$oncsyms --keep_isymbols=true --keep_osymbols=true $tmp_file_prefix.txt | fstcompose - $onc_boundary_fst | fstshortestpath | fstprint | sort -nr > $tmp_file_prefix.seq");
  
  open(PHONESSEQ, "$tmp_file_prefix.seq") || die("Failed to open $tmp_file_prefix.seq\n");
  my @syllable_marks;
  while($line = <PHONESSEQ>) {
    @fields = split(/\s+/, $line);
    if ($#fields >= 3) {
      push(@syllable_marks, $fields[3]);
    }
  }
  if ($#phonesonc ne $#syllable_marks) {
    print STDERR "Unmatched phones and syllable marks:\n( @phonesonc ) vs ( @syllable_marks )\n";
    exit(1);
  }
  $pron_sylbound = "";
  for (my $i = 0; $i <= $#syllable_marks; $i++) {
    $sylbound = "";
    if ($syllable_marks[$i] =~ /=/) {
      $sylbound = "\t";
    }
    ($phone, $onc) = split(/\//, $phonesonc[$i]);
    $pron_sylbound = $pron_sylbound . "$phone" . "$sylbound ";
  }
  return $pron_sylbound;
}
