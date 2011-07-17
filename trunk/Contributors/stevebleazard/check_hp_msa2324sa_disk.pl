#!/usr/bin/perl

# Copyright (c) 2011, Stephen Bleazard
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
# THE POSSIBILITY OF SUCH DAMAGE.


use Getopt::Long;
use Net::Telnet;

sub SASLogin {
  $telnet->open($_[0]);
  $telnet->waitfor(/(login|username)[: ]*$/i);
  $telnet->print("$_[1]");
  $telnet->waitfor(/password[: ]*$/i);
  $telnet->print("$_[2]");
  # either got a login or a prompt
  @ok = $telnet->waitfor(/(#|login:*) /i);
  if ($debug_commands == 1) { print "-"; print @ok; print "-\n"; }
  if ($ok[1] =~ m/login/gi)
  {
    return 0;
  }
  else
  {
    $telnet->print("stty rows 9999");
    $telnet->print("stty columns 255");
    return 1;
  }
}

sub usage () {
    print "Usage: ";
    print "$PROGNAME\n";
    print "   -H (--hostname)   Hostname to query - (required)\n";
    print "   -u (--username)   username \n";
    print "   -p (--password)   password\n";
    print "   -d (--disks)      disk1[,disk2]... - disks to check, defaults to all\n";
    print "   -s (--spares)     disk1:spare1[,disk2:spare2]... - check spares for specified disks\n";
    print "   -V (--version)    Plugin version\n";
    print "   -h (--help)       usage help\n\n" ;
}

$PROGNAME = $0;

Getopt::Long::Configure('bundling');
GetOptions
    ("h"   => \$opt_h, "help"         => \$opt_h,
     "u=s" => \$opt_u, "username=s"   => \$opt_u,
     "p=s" => \$opt_p, "password=s"   => \$opt_p,
     "d=s" => \$opt_d, "disks=s"      => \$opt_d,
     "s=s" => \$opt_s, "spares=s"     => \$opt_s,
     "V"   => \$opt_V, "version"      => \$opt_V,
     "H=s" => \$opt_H, "hostname=s"   => \$opt_H);

if ($opt_V) {
    print "$PROGNAME Version 1.0\n";
    exit(0);
}

if ($opt_h) {
    usage();
    exit(0);
}

%disks = ();
if (defined($opt_d))
{
  @l = split(/,/, $opt_d);
  foreach (@l) { $disks{$_}++; }
}

%spares = ();
if (defined($opt_s))
{
  my ($d,$c,@l);
  @l = split(/,/, $opt_s);
  foreach (@l)
  {
    ($d,$c) = split(/:/);
    if ($c !~ /^\d+$/) { print STDERR "spares options has format: disk:count[,disk:count]\n"; exit(0); }
    $spares{$d} = $c;
  }
}

$telnet = new Net::Telnet ( Timeout=>10, Errmode=>'die', Prompt => '/\# $/i');

if ( !SASLogin($opt_H, $opt_u, $opt_p) == 1 )
{
  print("Error: $opt_u user failed to log in. Exiting.\n");
  $telnet->close;
  exit(0);
}

@sV = $telnet->cmd("show vdisks");  $valid = 0;  $state = "s";  $exit_status = 0;
foreach (@sV)
{
  if ($state eq "s") { /Serial\s+Number/ and $state = "sl"; }
  elsif ($state eq "sl") { /^\-{60,}/ and $state = "b"; }
  else
  { 
    /^\-{60,}/ and last;
    ($name, $size, $free, $own, $pref, $raid, $disks, $spr, $chk, $status, $jobs, @p) = split(" ");
    defined($opt_d) && !defined($disks{$name}) && next;
    if (uc($status) eq "CRIT")
    {
      $exit_status = 2;
      if ($jobs eq "RCON") { $exit_message .= "$name not fault tolerant - rebuild $p[0]. "; }
      else { $exit_message .= "$name not fault tolerant. "; }
    }
    elsif (uc($status) eq "FTDN")
    {
      $exit_status = 2;
      if ($jobs eq "RCON")
        { $exit_message .= "$name fault tolerant w/failed disks - rebuild $p[0]. "; $exit_status == 0 and $exit_status = 1; }
      else  { $exit_message .= "$name fault tolerant w/failed disks. "; }
    }
    elsif (uc($status) eq "FTOL") { $exit_status = 0;  $exit_message .= "$name online. "; }
    elsif (uc($status) eq "OFFL") { $exit_status = 2;  $exit_message .= "$name offline and failed. "; }
    elsif (uc($status) eq "QTCR") { $exit_status = 2;  $exit_message .= "$name has been quarantined - missing disks. "; }
    elsif (uc($status) eq "QTOF") { $exit_status = 2;  $exit_message .= "$name has been quarantined - missing disks. "; }
    elsif (uc($status) eq "UP") { $exit_status = 0;  $exit_message .= "$name not fault tolerant. "; }
    else { $exit_status = 2;  $exit_message .= "$name unknown state: $status.  "; }
 
    if (defined($spares{$name}))
    {
      if ($spr < $spares{$name})
        { $exit_message .= "$name missing spare (is $spr expecting $spares{$name}).  "; $exit_status == 0 and $exit_status = 1; }
    }
  }
}
$exit_message eq "" and $exit_message = "Array OK";

print "$exit_message\n";
exit($exit_status);
