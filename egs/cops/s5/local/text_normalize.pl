#!/usr/bin/perl -w

#d-u-m-a-s

while (<>) {
  @A = split /\s+/, $_, 2;
  $A[1] =~ s/"//g;
  $A[1] =~ s/--/ /g;
  $A[1] =~ s/- -/ /g;
  $A[1] =~ s/\?//g;
  $A[1] =~ s/[,!;:\.]//g;
  $A[1] =~ s/ -$//g;
  $A[1] =~ s/ -/ /g;
  $A[1] =~ s/^- //g;
  $A[1] =~ s/- / /g;
  $A[1] =~ s/-$//g;
  $A[1] =~ s/^-//g;
  $A[1] = lc($A[1]);
  $A[1] =~ s/\[background voices\]/[noise]/g;
  $A[1] =~ s/\[background noise\]/[noise]/g;
  $A[1] =~ s/\[pause\]//g;
  $A[1] =~ s/\(pause\)//g;
  $A[1] =~ s/\[to dispatch\]//g;
  $A[1] =~ s/\[interposing\]//g;
  $A[1] =~ s/\[citizen\]//g;
  $A[1] =~ s/\[civilian\]//g;
  $A[1] =~ s/\[citizen's name\]//g;
  $A[1] =~ s/\[to citizen\]//g;
  $A[1] =~ s/\[officer\]//g;
  $A[1] =~ s/\[sighs\]//g;
  $A[1] =~ s/\[groans\]//g;
  $A[1] =~ s/\(groans\)//g;
  $A[1] =~ s/\[whispers\]//g;
  $A[1] =~ s/\[to dispatch\]//g;
  $A[1] =~ s/\[to unknown\]//g;
  $A[1] =~ s/\[returns to citizen\]//g;
  $A[1] =~ s/\[whistles\]/[noise]/g;

  print "$A[0] $A[1]";
}
