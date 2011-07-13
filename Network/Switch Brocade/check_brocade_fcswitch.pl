#!/usr/bin/perl -w

#
# $Id: check_brocade_fcswitch.pl 1 2010-03-09 10:48 mmueller / mindmaster315@a1.net
#
# Copyright (C) 2010 Martin Mueller,
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
# Report bugs to:  mindmaster315@a1.net
#
#
# CHANGELOG:
#
# 09.03.2010:
# First public version
#

$ENV{'PATH'}='';
$ENV{'BASH_ENV'}='';
$ENV{'ENV'}='';

use POSIX;
use warnings;
use strict;


# Find the Nagios::Plugin lib. Change this path if necessary
use FindBin;
use lib "$FindBin::Bin/../perl/lib";
use Nagios::Plugin qw(%ERRORS);

#use Net::SNMP qw(TRANSLATE_NONE);
use Net::SNMP;
use Getopt::Long qw(:config no_ignore_case bundling);

# define Constants

use vars qw($PROGRAMNAME $SHORTNAME $AUTHOR $VERSION);
$PROGRAMNAME = "$FindBin::Script";
$SHORTNAME = "Brocade FC-Switch Hardware";
$AUTHOR = "Martin Mueller";
$VERSION = '$Revision: 2 $';

sub usage();
sub help();

# define Commandline-Options

my $host = undef;
my $community = "public";
my $snmp_version = 1;
my $snmp_port = 161;
my $action = undef;
my $timeout = 15;
my $help = undef;
my $printversion = undef;


my $np = Nagios::Plugin->new(
                shortname => "$SHORTNAME",
);

# get Options

GetOptions(
   "H|host=s"           => \$host,
   "C|community=s"      => \$community,
   "p|snmp_port=i"      => \$snmp_port,
   "v|snmp_version=s"   => \$snmp_version,
   "t|timeout=i"        => \$timeout,
   "h|help"             => \$help,
   "V|version"          => \$printversion,
   );

if ($help) {
	help();
	}

if ($printversion) {
	printf "\n";
	printf "$PROGRAMNAME - $VERSION\n\n";
	printf "Copyright (C) 2010 $AUTHOR\n";
	printf "This programm comes with ABSOLUTELY NO WARRANTY\n";
	printf "This programm is licensed under the terms of the GNU General Public License";
	printf "\n\n";
	exit($ERRORS{'UNKNOWN'});
	}

if (!defined $host) {
	printf "\nMissing argument [host]. Please specify a hostname or ip address\n";
	usage();
	}

if ($snmp_version =~ /[^12c?]/) {
	printf "\nSNMP version: $snmp_version is not supported. Please use SNMP version 1 or 2\n";
	usage();
	}

# Just in case of problems, let's not hang Nagios
$SIG{'ALRM'} = sub {
	$np->nagios_die("No snmp response from $host (alarm)");
	};

alarm($timeout);

# ------------------------------------------------------
# Start here with Main Program
# ------------------------------------------------------

my $session;
my $error;

my $oid_num_sensors = ".1.3.6.1.4.1.1588.2.1.1.1.1.21.0";
my $oid_sensor_info = "1.3.6.1.4.1.1588.2.1.1.1.1.22.1.5.";
my $oid_sensor_value = "1.3.6.1.4.1.1588.2.1.1.1.1.22.1.4.";
my $oid_sensor_status = "1.3.6.1.4.1.1588.2.1.1.1.1.22.1.3.";
my $no_of_sensors = 0;
my $sensor_info = "";
my $sensor_value = 0;
my $sensor_status = 0;
my $i = 1;

my %possible_sensor_status = (
	1 => "unknown",
        2 => "faulty",
        3 => "below-min",
        4 => "normal",
        5 => "above-max",
        6 => "absent/missing"
	);

# Ajout EHE 2011.02.04 - support v2c
if($snmp_version =~ /^2c$/) {
	$snmp_version = 2;
}


&create_snmpsession();

$no_of_sensors = &get_snmpdata($oid_num_sensors);

while ($i<=$no_of_sensors) {
	$sensor_status = &get_snmpdata($oid_sensor_status,$i);
	$sensor_value = &get_snmpdata($oid_sensor_value,$i);
	$sensor_info = &get_snmpdata($oid_sensor_info,$i);

	if ($sensor_status == 1) {
		$np->add_message('UNKNOWN',$sensor_info." is ".$possible_sensor_status{$sensor_status});
		}
	elsif ($sensor_status == 2) {
		$np->add_message('CRITICAL',$sensor_info." is ".$possible_sensor_status{$sensor_status});
		}
	elsif ($sensor_status == 3) {
		$np->add_message('WARNING',$sensor_info." is ".$possible_sensor_status{$sensor_status});
		}
	elsif ($sensor_status == 4) {
		$np->add_message('OK',$sensor_info." is ".$possible_sensor_status{$sensor_status});
		}
	elsif ($sensor_status == 5) {
		$np->add_message('CRITICAL',$sensor_info." is ".$possible_sensor_status{$sensor_status});
		}
	elsif ($sensor_status == 6) {
		$np->add_message('WARNING',$sensor_info." is ".$possible_sensor_status{$sensor_status});
		}
	else {
		$np->add_message('UNKNOWN',$sensor_info." anything went wrong :-(");
		}

	$np->add_perfdata(
		label => $sensor_info,
		value => $sensor_value,
		);

	$i++;
	}

&end_snmpsession();

# Create Nagios-Output and End the Plugin

my ($code, $message) = $np->check_messages(join => "<BR>",join_all => "<BR>");
$np->nagios_exit($code,$message);

# ------------------------------------------------------
# End Main Program
# ------------------------------------------------------

sub create_snmpsession() {
	($session,$error) = Net::SNMP->session(Hostname => $host, Community => $community, Port => $snmp_port, Version => $snmp_version);
	$np->nagios_die("Unable to open SNMP connection. ERROR: $error") if (!defined($session));
	}

sub end_snmpsession() {
	$session->close;
	alarm(0);
	}

sub get_snmpdata() {
	my $oid_requested = $_[0];
	my $oid_option = $_[1];
	my $oid_value_hash;
	my $oid_value;
	my $session;
	my $error;

        ($session,$error) = Net::SNMP->session(Hostname => $host, Community => $community, Port => $snmp_port, Version => $snmp_version);
	$np->nagios_die("Unable to open SNMP connection. ERROR: $error") if (!defined($session));	

	# if OID-Option is given ask them, otherwise do oid only

	if (defined $oid_option) {
		$oid_value_hash = $session->get_request($oid_requested.$oid_option);
		$np->nagios_die("Unable to read SNMP-OID. ERROR: ".$session->error()) if (!defined($oid_value_hash));
        	$oid_value = $oid_value_hash->{$oid_requested.$oid_option};
		}
	else {
                $oid_value_hash = $session->get_request($oid_requested);
		$np->nagios_die("Unable to read SNMP-OID. ERROR: ".$session->error()) if (!defined($oid_value_hash));
                $oid_value = $oid_value_hash->{$oid_requested};
		}

        $session->close;
	alarm(0);

        return $oid_value;
        }

sub usage () {
	printf "\n";
	printf "$PROGRAMNAME -H <hostname> [-C <community>]\n\n";
	printf "Copyright (C) 2010 $AUTHOR\n";
	printf "This programm comes with ABSOLUTELY NO WARRANTY\n";
	printf "This programm is licensed under the terms of the GNU General Public License";
	printf "\n\n";
	exit($ERRORS{'UNKNOWN'});
	}

sub help () {
	printf "\n\n$PROGRAMNAME plugin for Nagios \n";
	printf "monitors hardware status of an Brocade Fibre-Switch 510 via SNMP.\n";
	printf "To use this Plugin your Brocade Swtich must have SNMP enabled.\n";
	printf "\nUsage:\n";
	printf "   -H (--hostname)   Hostname to query - (required)\n";
	printf "   -C (--community)  SNMP read community (default=public)\n";
	printf "   -v (--snmp_version)  1 for SNMP v1 (default)\n";
	printf "                        2 for SNMP v2c\n";
	printf "   -p (--snmp_port)  SNMP Port (default=161)\n";
	printf "   -t (--timeout)    Seconds before the plugin times out (default=15)\n";
	printf "   -V (--version)    Plugin version\n";
	printf "   -h (--help)       Usage help \n\n";
	exit($ERRORS{'OK'});
}

