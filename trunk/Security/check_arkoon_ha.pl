#!/usr/bin/perl

use strict;
use warnings;
use Nagios::Plugin;
use Data::Dumper;
use Net::OpenSSH;
use Switch;


my $plugin = Nagios::Plugin->new(
	usage 	=> "Usage: %s -H <host> [-u <ssh-username>] [-p <ssh-port>] -t <HA-type>",
	version => '0.1',
	blurb	=> 'Script to check Arkoon HA',
	plugin	=> 'check_arkoon_ha',
	url	=> 'Created by Marc GUYARD <m.guyard@orange.com>',
	timeout	=> '15'
);

$plugin->add_arg(
	spec		=> 'host|H=s',
	help		=> "-H, --host=ADDRESS\n   Address of device",
	required	=> 1
);

$plugin->add_arg(
	spec		=> 'username|u=s',
	help		=> "-u, --username=STRING\n   SSH Username",
	default		=> 'root'
);

$plugin->add_arg(
	spec		=> 'port|p=s',
	help		=> "-p, --port=INTEGER\n   SSH Port",
	default		=> '822'
);

$plugin->add_arg(
	spec		=> 'type|t=s',
	help		=> "-t, --type=STRING\n   HA Type (active/passive)",
	required	=> 1
);

$plugin->getopts();
my $opts = $plugin->opts();

$SIG{ALRM} = sub {
	$plugin->nagios_exit(UNKNOWN, "Timeout reached");
};
alarm $opts->get('timeout');

my $host			= $opts->get('host');
my $username		= $opts->get('username');
my $port			= $opts->get('port');
my $ha_type			= lc($opts->get('type'));
my $verbose			= $opts->get('verbose');

if ($ha_type !~ /^(active|passive)$/ ) {
	$plugin->nagios_exit(UNKNOWN, "Invalid HA Type Argument (".$ha_type.") - Only active or passive is valid");
} else {
	#$Net::OpenSSH::debug = -1 if $verbose;
	my $ssh;
	$ssh = Net::OpenSSH->new($host,
		user		=> $username,
		port		=> $port,
		kill_ssh_on_timeout => 1,
		timeout		=> 600,
	);
	$plugin->nagios_exit(UNKNOWN, "SSH connection impossible on ".$host." (Error: ".$ssh->error.")") if ( $ssh->error );
	# Recuperation du status HA
	my $ha_status = $ssh->capture("/etc/init.d/akha status");
	print $ha_status if $verbose;
	$ha_status =~ m/this node is currently (\w+)\s\D(\X+)\D\n/;
	my $actual_status = $1;
	my $actual_status_description = $2;
	print "Status : ".$actual_status."/ Description : ".$actual_status_description."\n" if $verbose;
	if ($ha_type !~ $actual_status ) {
		$plugin->add_message(CRITICAL, "The device is not in ".$ha_type." state (actually : ".$actual_status.")");
	} else {
		if ( $actual_status =~ "active" ) {
			if ( $actual_status_description =~ /[1-9]+ client connected/ ) {
				$plugin->add_message(OK, "Device is ".$actual_status.". ".$actual_status_description);
			} else {
				$plugin->add_message(CRITICAL, "Device is ".$actual_status." but ".$actual_status_description);
			}
		} elsif ( $actual_status =~ "passive" ) {
			if ( $actual_status_description =~ "connected to active node" ) {
				$plugin->add_message(OK, "Device is ".$actual_status.". ".$actual_status_description);
			} else {
				$plugin->add_message(CRITICAL, "Device is ".$actual_status." but ".$actual_status_description);
			}
		}
	}
}

my ($code, $message) = $plugin->check_messages();
$plugin->nagios_exit($code, $message);
