#!/usr/bin/perl

# $Id$

use strict;
use warnings;
use Nagios::Plugin;
use Data::Dumper;
use Net::DNS;
use Net::DNS::RR;
use Switch;

# Definition des options
my $plugin = Nagios::Plugin->new(
	usage 	=> "Usage: %s -n <domain-name> -s <dns-server>",
	version => '0.1',
	blurb	=> 'Script to check DNS SOA in a domain',
	plugin	=> 'check_dns_soa.pl',
	url	=> 'Created by Marc GUYARD <m.guyard@orange.com>',
	timeout	=> '15'
);

$plugin->add_arg(
	spec		=> 'domain|n=s',
	help		=> "-n, --domain=DOMAIN-NAME\n   Domain Name",
	required	=> 1
);

$plugin->add_arg(
	spec		=> 'server|s=s',
	help		=> "-s, --server=SERVER\n   domain name server to query (master for your domain name)",
	required	=> 1
);

$plugin->getopts();
my $opts = $plugin->opts();

$SIG{ALRM} = sub {
	$plugin->nagios_exit(CRITICAL, "Timeout reached");
};
alarm $opts->get('timeout');

# Recuperation des options
my $domain			= $opts->get('domain');
my $server			= $opts->get('server');
my $verbose			= $opts->get('verbose');

## Get domain name from user.
my $objResolve = Net::DNS::Resolver->new;

## If debug requested, turn it on inside Net::DNS
if ($verbose) {
	#  $objResolve->debug(1);
}

## We need to work out which nameservers are responsible for
#  this domain name.  Put the nameservers in a perl list
#  called @nameservers
my @nameservers;
$objResolve->nameservers($server);
my $query = $objResolve->query("$domain", "NS");

if ($query) {
	foreach my $rr (grep { $_->type eq 'NS' } $query->answer) {
		push @nameservers,$rr->nsdname;
		print "Nameserver to query: " . $rr->nsdname, "\n" if $verbose;
	}
} else {
	$plugin->nagios_exit(CRITICAL, "Query Failed ".$objResolve->errorstring);
}

## Also find the SOA serial number to use as the master serial.
my $master;
$query  = $objResolve->query("$domain", "SOA");
foreach my $rr (grep { $_->type eq 'SOA' } $query->answer) {
	$master = $rr->serial;
	print "Master serial number from ".$server." is $master\n" if $verbose;
}

foreach my $nameserver (@nameservers) {
	next if ($nameserver eq $server);
	print "Checking server ... $nameserver\n" if $verbose;
	my $objChildResolve = Net::DNS::Resolver->new;
	#  $objChildResolve->debug(1) if $verbose;
	$objChildResolve->nameservers("$nameserver");
	my $query        = $objChildResolve->query("$domain", "SOA");
	foreach my $rr (grep { $_->type eq 'SOA' } $query->answer) {
		my $childserial = $rr->serial;
		$childserial = "0";
		print "Serial number from $nameserver is $childserial\n" if $verbose;
		if ($childserial != $master) {
			$plugin->add_message( CRITICAL, $nameserver." serves Serial ".$childserial." not ".$master);
		} else {
			$plugin->add_message( OK, $nameserver." serves Serial ".$childserial." like master serial ".$master);
		}
	}
}

my ($code, $message) = $plugin->check_messages(join_all => 1, join => ' / ', ok => 'All SOA are the same : '.$master);
$plugin->nagios_exit($code, $message);