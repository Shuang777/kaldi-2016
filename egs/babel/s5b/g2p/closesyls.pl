#!/usr/bin/perl

#
# call this as:
#  ./closesyls.pl syllablelist neededsyllablelist
#
# The alignment scores are controlled through the 
# featuredistance function.  This function is able to see
# both the phone and syllable position (O/N/C) of segments
# being compared.  The distance is based on the number of features
# in common between segments, with arbitrary costs for insertions/deletions.
#
# Modifications should be made in that function (at the bottom of the file).

BEGIN {
    @INC=("/n/shokuji/da/suhang/local/g2p");
}

require string_aligner;

$syllablelist=shift(@ARGV);
$neededsyls=shift(@ARGV);

open(SYLLABLELIST,"$syllablelist");
while(<SYLLABLELIST>) {
  chomp;
  @p=&markonc(split(/=/,$_));
  push(@syls,[@p]);
}
close(SYLLABLELIST);

# this is the stupid way to do it -- check against all syllables

$aligner=&string_aligner::new();

$aligner->string_aligner::set_metric(\&featuredistance);


open(NEEDED, $neededsyls) || die("Can't open $neededsyls for reading");
while(<NEEDED>) {
  chomp;
  $p=[&markonc(split(/=/,$_))];
  
  $bestscore=100000000000000000000;
  foreach $s (@syls) {
    $score=$aligner->string_aligner::get_string_score($p,$s);
#    print join("=",@{$p}),"\t",join("=",@{$s}),"\t$score\n";
    if ($score<$bestscore) {
        $bestsyl=$s;
        $bestscore=$score;
    }
  }
  print &striponc($p)," ",&striponc($bestsyl),"\n";
}


exit(0);

sub markonc {
  my @pron=@_;

  my $onset=1;
  my @out=();

  my $p;
  foreach $p (@pron) {
    if($featuremap{$p}=~/vowel/) {
        $onset=0;
        push(@out,"$p N");
    } elsif ($onset) {
        push(@out,"$p O");
    } else {
        push(@out,"$p C");
    }
  }

  return @out;
}

sub striponc {
  my @pron=@{$_[0]};
  
  my @out=();
  my $p;
  
  foreach $p (@pron) {
    my $p2=$p;
    $p2=~s/ [ONC]$//;
#    print "\t$p => $p2\n";
    push(@out,$p2);
  }
  return join("=",@out);
}
    


BEGIN {
%featuremap=(
"a"=>"open front unrounded vowel",
"b"=>"voiced bilabial plosive",
"b_<"=>"voiced bilabial implosive",
"c"=>"voiceless palatal plosive",
"d"=>"voiced alveolar plosive",
"d`"=>"voiced retroflex plosive",
"d_<"=>"voiced alveolar implosive",
"e"=>"close-mid front unrounded vowel",
"f"=>"voiceless labiodental fricative",
"g"=>"voiced velar plosive",
"g_<"=>"voiced velar implosive",
"h"=>"voiceless glottal fricative",
"h\\"=>"voiced glottal fricative",
"i"=>"close front unrounded vowel",
"j"=>"palatal approximant",
"j\\"=>"voiced palatal fricative",
"k"=>"voiceless velar plosive",
"l"=>"alveolar lateral approximant",
"l`"=>"retroflex lateral approximant",
"l\\"=>"alveolar lateral flap",
"m"=>"bilabial nasal",
"n"=>"alveolar nasal",
"n`"=>"retroflex nasal",
"o"=>"close-mid back rounded vowel",
"p"=>"voiceless bilabial plosive",
"p\\"=>"voiceless bilabial fricative",
"q"=>"voiceless uvular plosive",
"r"=>"alveolar trill",
"r`"=>"retroflex flap",
"r\\"=>"alveolar approximant",
"r\\`"=>"retroflex approximant",
"s"=>"voiceless alveolar fricative",
"s`"=>"voiceless retroflex fricative",
"s\\"=>"voiceless alveolo-palatal fricative",
"t"=>"voiceless alveolar plosive",
"t`"=>"voiceless retroflex plosive",
"u"=>"close back rounded vowel",
"v"=>"voiced labiodental fricative",
"v\\"=>"labiodental approximant",
"w"=>"labial-velar approximant",
"x"=>"voiceless velar fricative",
"x\\"=>"voiceless palatal-velar fricative",
"y"=>"close front rounded vowel",
"z"=>"voiced alveolar fricative",
"z`"=>"voiced retroflex fricative",
"z\\"=>"voiced alveolo-palatal fricative",
"A"=>"open back unrounded vowel",
"B"=>"voiced bilabial fricative",
"B\\"=>"bilabial trill",
"C"=>"voiceless palatal fricative",
"D"=>"voiced dental fricative",
"E"=>"open-mid front unrounded vowel",
"F"=>"labiodental nasal",
"G"=>"voiced velar fricative",
"G\\"=>"voiced uvular plosive",
"G\\_<"=>"voiced uvular implosive",
"H"=>"labial-palatal approximant",
"H\\"=>"voiceless epiglottal fricative",
"I"=>"near-close near-front unrounded vowel",
"I\\"=>"near-close central unrounded vowel",
"J"=>"palatal nasal",
"J\\"=>"voiced palatal plosive",
"J\\_<"=>"voiced palatal implosive",
"K"=>"voiceless alveolar lateral fricative",
"K\\"=>"voiced alveolar lateral fricative",
"L"=>"palatal lateral approximant",
"L\\"=>"velar lateral approximant",
"M"=>"close back unrounded vowel",
"M\\"=>"velar approximant",
"N"=>"velar nasal",
"N\\"=>"uvular nasal",
"O"=>"open-mid back rounded vowel",
"O\\"=>"bilabial click",
"P"=>"labiodental approximant",
"Q"=>"open back rounded vowel",
"R"=>"voiced uvular fricative",
"R\\"=>"uvular trill",
"S"=>"voiceless postalveolar fricative",
"T"=>"voiceless dental fricative",
"U"=>"near-close near-back rounded vowel",
"U\\"=>"near-close central rounded vowel",
"V"=>"open-mid back unrounded vowel",
"W"=>"voiceless labial-velar fricative",
"X"=>"voiceless uvular fricative",
"X\\"=>"voiceless pharyngeal fricative",
"Y"=>"near-close near-front rounded vowel",
"Z"=>"voiced postalveolar fricative",
"@"=>"schwa",
"@\\"=>"close-mid central unrounded vowel",
"{"=>"near-open front unrounded vowel",
"}"=>"close central rounded vowel",
"1"=>"close central unrounded vowel",
"2"=>"close-mid front rounded vowel",
"3"=>"open-mid central unrounded vowel",
"3\\"=>"open-mid central rounded vowel",
"4"=>"alveolar flap",
"5"=>"velarized alveolar lateral approximant; also see _e",
"6"=>"near-open central vowel",
"7"=>"close-mid back unrounded vowel",
"8"=>"close-mid central rounded vowel",
"9"=>"open-mid front rounded vowel",
"&"=>"open front rounded vowel",
"?"=>"glottal stop",
"?\\"=>"voiced pharyngeal fricative"
    );
}

sub featuredistance {
  my ($p1,$s1)=split(/ /,$_[1]);
  my ($p2,$s2)=split(/ /,$_[2]);


  # This block (and the next) gives the arbitrary
  # distances for not matching a phone.
  # Coda consonants cost less than nuceli, which cost lest than
  # onsets.  This can be changed if needed.
  if ($p1 eq "INS" || $p1 eq "DEL") {
    $f2=$featuremap{$p2};
    # prefer C > O > N
    if ($f2=~/vowel/) {
        return 2;
    } elsif ($s2 eq "C") {
        return 0.5;
    } else {
        return 1;
    }
  }

  if ($p2 eq "INS" || $p2 eq "DEL") {
    $f1=$featuremap{$p1};
    # prefer C > O > N
    if ($f1=~/vowel/) {
        return 2;
    } elsif ($s1 eq "C") {
        return 0.5;
    } else {
        return 1;
    }
  }
    
  # Gather features in both phones
  my %m=();
  my @feats=(split(/ /,$featuremap{$p1}),
         split(/ /,$featuremap{$p2}));
  my $f;
  foreach $f (@feats) {
    $m{$f}=$m{$f}+1;
  }
  my $total=0;
  my $count=0;

  # Count number of features in common - when number of features
  # is 2 then both phones share that feature.
  foreach $f (keys %m) {
    if ($m{$f}!=2) {
        $total++;
    }
    $count++;
  }
  
  # This is just in case there is a missing map.
  if ($count==0) {
    return 2; #shouldn't get here
  } else {
    # Add a penalty if there is a syllable position mismatch
    if ($s1 ne $s2) {
      $total+=$count;
    }
  # Return the fraction of mismatching features (+ penalty)
  return $total/$count;
  }    
}
