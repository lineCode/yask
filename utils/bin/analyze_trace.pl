#!/usr/bin/env perl

##############################################################################
## YASK: Yet Another Stencil Kernel
## Copyright (c) 2014-2018, Intel Corporation
## 
## Permission is hereby granted, free of charge, to any person obtaining a copy
## of this software and associated documentation files (the "Software"), to
## deal in the Software without restriction, including without limitation the
## rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
## sell copies of the Software, and to permit persons to whom the Software is
## furnished to do so, subject to the following conditions:
## 
## * The above copyright notice and this permission notice shall be included in
##   all copies or substantial portions of the Software.
## 
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
## FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
## IN THE SOFTWARE.
##############################################################################

# Purpose: Process the output of a log from a binary and compare every grid write.
# Build with the following options:
# OMPFLAGS='-qopenmp-stubs' YK_CXXOPT='-O0' arch=intel64 EXTRA_MACROS='CHECK TRACE TRACE_MEM FORCE_SCALAR' real_bytes=8
# Run with '-v'.

use strict;
use File::Basename;
use lib dirname($0)."/lib";
use lib dirname($0)."/../lib";

my $in_perf = 0;
my $in_val = 0;
my $key = undef;
my %vals;
my %pts;
my %writes;

while (<>) {

  if (/Trial number:\s*(\d+)/) {
    $key = ($1 == 1) ? 'perf' : undef;
  }

  elsif (/Running.*for validation/) {
    $key = 'val';
  }

  elsif (/Checking results/) {
    undef $key;
  }

  # writeElem: pressure[t=0, x=0, y=0, z=0] = 5.7 at line 287
  elsif (/writeElem:\s*(\w+)\[(.*)\]\s*=\s*(\S+)/) {
    my ($grid, $indices, $val) = ($1, $2, $3);
    if (defined $key) {
      $indices =~ s/\b\d\b/0$&/g;

      # track last value.
      $vals{$key}{$grid}{$indices} = $val;

      # track all pts written.
      $pts{$grid}{$indices} = 1;

      # track writes in order.
      push @{$writes{$key}}, [ $grid, $indices ];
    }
  }

  elsif (/PASS|FAIL|DONE/) {
    print $_;
  }
}
my $nissues = 0;

sub comp($$) {
  my $grid = shift;
  my $indices = shift;

  print "$grid\[$indices\] =";
  my $pval;
  for my $key (qw(perf val)) {
    my $val = $vals{$key}{$grid}{$indices};
    if (defined $val) {
      print "\t $val";
      if (defined $pval && $pval) {
        my $pctdiff = ($pval - $val) / $pval * 100.0;
        print "\t diff = $pctdiff %";
        if (abs($pctdiff) > 5) {
          print " <<<<";
          $nissues++;
        }
      }
      $pval = $val;
    } else {
      print " NOT written in $key";
      $nissues++;
    }
  }
  print "\n";
}

print "\n===== Comparisons in perf-write order =====\n".
  "(Will not show missing writes.)\n";
print "Values are from perf, then validation trial\n";
my %nwrites;
for my $pw (@{$writes{perf}}) {
  my ($grid, $indices) = ($pw->[0], $pw->[1]);
  comp($grid, $indices);
  my $nw = ++$nwrites{$grid}{$indices};
  if ($nw > 1) {
    print "^^^^^^^^ $nw writes!!!\n";
    $nissues++;
  }
}

print "\n===== Comparisons in grid & index order =====\n";
print "Values are from perf, then validation trial\n";
for my $grid (sort keys %pts) {
  for my $indices (sort keys %{$pts{$grid}}) {
    comp($grid, $indices);
  }
}

print "\n$0:\n";
for my $key (sort keys %writes) {
  print " ".(scalar @{$writes{$key}})." $key write(s) checked.\n";
}
print " $nissues issue(s) flagged.\n";
print " (Not all issues may be problematic if using temporal tiling and MPI.)\n"
  if $nissues;
exit $nissues;
