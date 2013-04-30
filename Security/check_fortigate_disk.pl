#!/usr/bin/perl

# $Id$

use strict;
use warnings;
use Nagios::Plugin;
use Data::Dumper;
use Net::SNMP;
use Switch;


my $plugin = Nagios::Plugin->new(
	usage 	=> "Usage: %s -H <host> [-P <version>] -C <snmp_community> -w <warning> -c <critical>",
	version => '0.1',
	blurb	=> 'Script to check Dsik Usage',
	plugin	=> 'check_fortigate_disk',
	url	=> 'Created by Marc GUYARD <m.guyard@orange-ftgroup.com>',
	timeout	=> '15'
);

$plugin->add_arg(
	spec		=> 'host|H=s',
	help		=> "-H, --host=ADDRESS\n   Address of device",
	required	=> 1
);

$plugin->add_arg(
	spec		=> 'snmpver|P=s',
	help		=> "-P, --snmpver=STRING\n   SNMP Version (1/2c) - *SNMP v3 not supported yet*"
);

$plugin->add_arg(
	spec		=> 'community|C=s',
	help		=> "-C, --community=STRING\n   SNMP Community Name"
);

$plugin->add_arg(
	spec		=> 'warning|w=s',
	help		=> "-w, --warning=INTEGER\n   Warning threshold",
	required	=> 1
);

$plugin->add_arg(
	spec		=> 'critical|c=s',
	help		=> "-c, --critical=INTEGER\n   Critical threshold",
	required	=> 1
);

$plugin->getopts();
my $opts = $plugin->opts();

$SIG{ALRM} = sub {
	$plugin->nagios_exit(CRITICAL, "Timeout reached");
};
alarm $opts->get('timeout');

my $host			= $opts->get('host');
my $snmpver			= $opts->get('snmpver');
my $community			= $opts->get('community');
my $warning_threshold		= $opts->get('warning');
my $critical_threshold		= $opts->get('critical');
my $verbose			= $opts->get('verbose');

my $oid_disksize = ".1.3.6.1.4.1.12356.101.4.1.7.0";
my $oid_diskusage = ".1.3.6.1.4.1.12356.101.4.1.6.0";

my ($session, $error) = Net::SNMP->session(
		-hostname 	=> $host,
		-community	=> $community,
		-version	=> $snmpver,
);
$plugin->nagios_exit(CRITICAL, "No response from server ".$host." (Error: ".$error.")") unless ( $session );
my $disksize_result = $session->get_request( -varbindlist => [ $oid_disksize ] );
if (!defined $disksize_result) {
	$plugin->nagios_exit(WARNING, "Unable to bind oid DiskSize (".$oid_disksize.")");
	print "DEBUG: ".$session->error() if $verbose;
	$session->close();
	exit 1;
}

print "DUMP\n****************\n".Dumper($oid_disksize)."\n\n\n" if $verbose ;
my $disk_size = $disksize_result->{$oid_disksize};

if ( $disk_size eq 0 ) {
	$plugin->add_message(OK, "No disk in this type of appliance");
} else {
	my $diskusage_result = $session->get_request( -varbindlist => [ $oid_diskusage ] );
	if (!defined $disksize_result) {
		$plugin->nagios_exit(WARNING, "Unable to bind oid DiskUsage (".$oid_disksize.")");
		print "DEBUG: ".$session->error() if $verbose;
		$session->close();
		exit 1;
	}
	print "DUMP\n****************\n".Dumper($oid_diskusage)."\n\n\n" if $verbose ;
	my $disk_usage = $diskusage_result->{$oid_diskusage};
	print "Disk Usage : ".$disk_usage."\n" if $verbose;
	#my $disk_usage = "50";
	print "Disk Size : ".$disk_size."\n" if $verbose;
	#my $disk_size = "200";
	######
	my $disk_percent = int($disk_usage / $disk_size * 100 + 0.5);
	print "Usage disk : ".$disk_percent."%\n" if $verbose ;
	# Threshold methods 
	my $threshold = $plugin->set_thresholds(
		warning => $warning_threshold,
		critical => $critical_threshold,
	);
	my $status = $threshold->get_status($disk_percent);
	print "Status : ".$status."\n" if $verbose;

	# Performance
	$plugin->add_perfdata(
		label => "size",
		value => $disk_size,
		uom => "mB",
	);
        $plugin->add_perfdata(
                label => "used",
                value => $disk_usage,
                uom => "mB",
                warning => $warning_threshold,
                critical => $critical_threshold,
                min => 0,
                max => $disk_size,
        );	

	switch ($status) {
		case 0 { $plugin->add_message(OK, $disk_percent."%"); }
		case 1 { $plugin->add_message(WARNING, "threshold (".$warning_threshold."%) excedeed - ".$disk_percent." %"); }
		case 2 { $plugin->add_message(CRITICAL, "threshold (".$critical_threshold.") excedeed - ".$disk_percent." %"); }
		case 3 { $plugin->add_message(CRITICAL, "Unknown error"); }
	}

}

my ($code, $message) = $plugin->check_messages();
$plugin->nagios_exit($code, $message);
