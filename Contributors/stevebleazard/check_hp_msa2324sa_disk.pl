#!/usr/bin/perl

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
