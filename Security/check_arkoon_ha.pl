#!/usr/bin/perl

# $Id$

use strict;
use warnings;
use Nagios::Plugin;
use Data::Dumper;
use Net::OpenSSH;
use Switch;


my $plugin = Nagios::Plugin->new(
	usage 	=> "Usage: %s -H <host> [-u <ssh-username>] [-p <ssh-port>] -s <HA-state> -t <ha-type>",
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
	spec		=> 'state|s=s',
	help		=> "-s, --state=STRING\n   HA State (active/passive)",
	required	=> 1
);

$plugin->add_arg(
	spec		=> 'type|t=s',
	help		=> "-t, --type=STRING\n   Ha Type (akha/vrrp)",
	required	=> 1
);

$plugin->getopts();
my $opts = $plugin->opts();

$SIG{ALRM} = sub {
	$plugin->nagios_exit(CRITICAL, "Timeout reached");
};
alarm $opts->get('timeout');

my $ssh;
my $host			= $opts->get('host');
my $username		= $opts->get('username');
my $port			= $opts->get('port');
my $ha_state		= lc($opts->get('state'));
my $ha_type			= lc($opts->get('type'));
my $verbose			= $opts->get('verbose');

# Fonction de sortie Nagios
sub nagios_end {
	my ($code, $message) = $plugin->check_messages();
	$plugin->nagios_exit($code, $message);
}

# Validation de parametres
if ($ha_type !~ /^(akha|vrrp)$/ ) {
	$plugin->nagios_exit(WARNING, "Invalid HA Type Argument (".$ha_type.") - Only akha (Arkoon v4) or vrrp (Arkoon v5) is valid");
	&nagios_end;
}
if ($ha_state !~ /^(active|passive)$/ ) {
	$plugin->nagios_exit(WARNING, "Invalid HA State Argument (".$ha_state.") - Only active or passive is valid");
	&nagios_end;
}


# Connection SSH pour recuperer le retour du HA
#$Net::OpenSSH::debug = -1 if $verbose;
$ssh = Net::OpenSSH->new($host,
	user		=> $username,
	port		=> $port,
	kill_ssh_on_timeout => 1,
	timeout		=> 600,
);
$plugin->nagios_exit(UNKNOWN, "SSH connection impossible on ".$host." (Error: ".$ssh->error.")") if ( $ssh->error );

switch ($ha_type) {
	case "akha" { &akha_verify };
	case "vrrp" { &vrrp_verify };
}


sub akha_verify {
	# Recuperation du status HA
	my $ha_status = $ssh->capture("/etc/init.d/akha status");
	print $ha_status if $verbose;
	$ha_status =~ m/this node is currently (\w+)\s\D(\X+)\D\n/;
	my $actual_status = $1;
	my $actual_status_description = $2;
	print "Status : ".$actual_status."/ Description : ".$actual_status_description."\n" if $verbose;
	if ($ha_state !~ $actual_status ) {
		$plugin->add_message(CRITICAL, "The device is not in ".$ha_state." state (actually : ".$actual_status.")");
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

sub vrrp_verify {
	# Recuperation du status HA
	my $actual_status = $ssh->capture("/opt/arkoon/bin/vrrp -c");
	chomp($actual_status);
	print $actual_status if $verbose;
	switch ($actual_status) {
		case "MASTER" { $actual_status = "active" };
		case "SLAVE" { $actual_status = "passive" };
	}
	if ( $actual_status !~ $ha_state ) {
		$plugin->add_message(CRITICAL, "The device is not in ".$ha_state." state (actually : ".$actual_status.")");
	} else {
		$plugin->add_message(OK, "Device is ".$actual_status);
	}
}

# Sortie Nagios
&nagios_end;
