#!/usr/bin/perl

# $Id$

use strict;
use warnings;
use Nagios::Plugin;
use Data::Dumper;
use Net::SNMP;

my $plugin = Nagios::Plugin->new(
	usage 	=> "Usage: %s -H <host> [-v <version>] -C <snmp_community>",
	version => '0.1',
	blurb	=> 'Script to check BGP Peer',
	plugin	=> 'check_snmp_bgp-peer',
	url		=> 'Created by Marc GUYARD <m.guyard@orange-ftgroup.com>',
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

$plugin->getopts();
my $opts = $plugin->opts();

$SIG{ALRM} = sub {
	$plugin->nagios_exit(UNKNOWN, "Timeout reached");
};
alarm $opts->get('timeout');

my $host		= $opts->get('host');
my $snmpver		= $opts->get('snmpver');
my $community	= $opts->get('community');
my $verbose		= $opts->get('verbose');

my $oid_peer = ".1.3.6.1.2.1.15.3.1.7";
my $oid_peerstatus = ".1.3.6.1.2.1.15.3.1.2";
my @oid_peerstatus_table = ("","idle", "connect", "active", "opensent", "openconfirm", "established");

my ($session, $error) = Net::SNMP->session(
		-hostname 	=> $host,
		-community	=> $community,
		-version	=> $snmpver,
);
$plugin->nagios_exit(UNKNOWN, "No response from server ".$host." (Error: ".$error.")") unless ( $session );
my $bgppeer_result = $session->get_table( -baseoid => $oid_peer, );
if (!defined $bgppeer_result) {
	$plugin->nagios_exit(UNKNOWN, "Unable to bind oid (".$oid_peer.")");
	print "DEBUG: ".$session->error() if $verbose;
	$session->close();
	exit 1;
}

print "DUMP\n****************\n".Dumper($bgppeer_result)."\n\n\n" if $verbose ;
my %peer_address = %{$bgppeer_result};

foreach my $peer_addressIP (values %peer_address) {
	print "Peer Address : ".$peer_addressIP."\n" if $verbose;
	my $bgp_peerstate = $session->get_request( -varbindlist => [$oid_peerstatus.".".$peer_addressIP] );
	my $bgp_peerstatus = $bgp_peerstate->{$oid_peerstatus.".".$peer_addressIP};
	my $bgp_peerstatus_description = $oid_peerstatus_table[$bgp_peerstatus];
	print "Peer Status ID : ".$bgp_peerstatus."\n" if $verbose;
	print "Peer Status Description : ".$bgp_peerstatus_description."\n" if $verbose;
	if ( $bgp_peerstatus eq 1 ) {
		$plugin->add_message(CRITICAL, $peer_addressIP." in state ".$bgp_peerstatus_description.", ");
	}
	if ( ($bgp_peerstatus gt 1) && ($bgp_peerstatus lt 6) ) {
		$plugin->add_message(WARNING, $peer_addressIP." in state ".$bgp_peerstatus_description.", ");
	}
	if ( $bgp_peerstatus eq 6 ) {
		$plugin->add_message(OK, $peer_addressIP." OK");
	}
}

my ($code, $message) = $plugin->check_messages();
$message = "All BGP Peers are established" if $code == 0;
$plugin->nagios_exit($code, $message);
