#!/usr/bin/perl

# $Id$

use strict;
use warnings;
use Nagios::Plugin;
use Data::Dumper;
use POSIX;
use WWW::Mechanize;
use XML::Simple;
use Switch;

# Definition des options
my $plugin = Nagios::Plugin->new(
	usage 	=> "Usage: %s -H <host> -P <webUI_Port> -u <username> -p <password>",
	version => '0.3',
	blurb	=> 'Script to check Bluecoat Health-Check Status',
	plugin	=> 'check_bluecoat_healthcheck.pl',
	url	=> 'Created by Marc GUYARD <m.guyard@orange.com>',
	timeout	=> '15'
);

$plugin->add_arg(
	spec		=> 'host|H=s',
	help		=> "-H, --host=ADDRESS\n   Address of device",
	required	=> 1
);

$plugin->add_arg(
	spec		=> 'port|P=i',
	help		=> "-P, --port=INTEGER\n   Port WebUI",
	required	=> 1
);

$plugin->add_arg(
	spec		=> 'username|u=s',
	help		=> "-u, --username=STRING\n   WebUI Username",
	required	=> 1
);

$plugin->add_arg(
	spec		=> 'password|p=s',
	help		=> "-p, --password=STRING\n   WebUI Password",
	required	=> 1
);

$plugin->getopts();
my $opts = $plugin->opts();

$SIG{ALRM} = sub {
	$plugin->nagios_exit(CRITICAL, "Timeout reached");
};
alarm $opts->get('timeout');

# Recuperation des options
my $host			= $opts->get('host');
my $port			= $opts->get('port');
my $username		= $opts->get('username');
my $password		= $opts->get('password');
my $verbose			= $opts->get('verbose');

# Recuperation du XML des Health-Check
$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0; # Permet de ne plus verifier le certificat
my $mech = WWW::Mechanize->new(
	agent => 'Supervision NSOC NIS' ,
	autocheck => 0
);
my $XML_HealthCheck_URL = "https://".$host.":".$port."/health_check/statistics_xml";
my $XML_HealthCheck_Content;
$mech->credentials( $username => $password );
$mech->get( $XML_HealthCheck_URL );
if ( $mech->success ) {
	print "DEBUG : XML Health-Check retreived" if $verbose;
	$XML_HealthCheck_Content = $mech->content();
} else {
	$plugin->nagios_exit(CRITICAL, "Failed to retreive the XML Health-Check status with error (".$mech->response->status_line.")");
}

# Parsing du XML
my $xml = new XML::Simple;
my $XML_HealthCheck = $xml->XMLin( $XML_HealthCheck_Content, suppressempty => '' );
print "Module XML Dump\n****************\n".Dumper($XML_HealthCheck) if $verbose;

my $HealthCheck_Disabled = 0;
my $HealthCheck_Error = 0;
my $HealthCheck_OK = 0;
foreach my $HealthCheck (@{$XML_HealthCheck->{HealthCheck}}) {
	my $HealthCheck_lastcheck = strftime("%d-%m-%Y %H:%M:%S" , localtime($HealthCheck->{Last}->{When}) );
	
	print "****\nName : ".$HealthCheck->{Name}."\nEnable : ".$HealthCheck->{Enable}."\nStatut : ".$HealthCheck->{Status}."`\nMessage : ".$HealthCheck->{Health}."\nType : ".$HealthCheck->{Type}."\nLast check : ".$HealthCheck_lastcheck."\n****\n\n" if $verbose;
	switch ($HealthCheck->{Enable}) {
		case "Enabled" {
			if ( $HealthCheck->{Status} ne "OK" ) {
				$plugin->add_message( CRITICAL, "The Health-Check ".$HealthCheck->{Name}." is in state ".$HealthCheck->{Status}." with message '".$HealthCheck->{Health}."' (Type : ".$HealthCheck->{Type}.")" );
				$HealthCheck_Error += 1;
			} else {
				$plugin->add_message( OK, "The Health-Check ".$HealthCheck->{Name}." is in state ".$HealthCheck->{Status}." with message '".$HealthCheck->{Health}."' (Type : ".$HealthCheck->{Type}.")" );
				$HealthCheck_OK += 1;
			}
		} else {
			$plugin->add_message( OK, "The Health-Check ".$HealthCheck->{Name}." is in state ".$HealthCheck->{Status}." with message '".$HealthCheck->{Health}."' (Type : ".$HealthCheck->{Type}.")" );
			$HealthCheck_Disabled += 1;
		}
	}
}

# Performance
$plugin->add_perfdata(
	label => "OK",
	value => $HealthCheck_OK,
	uom => "",
);
$plugin->add_perfdata(
	label => "Error",
	value => $HealthCheck_Error,
	uom => "",
);	
$plugin->add_perfdata(
	label => "Disabled",
	value => $HealthCheck_Disabled,
	uom => "",
);

my ($code, $message) = $plugin->check_messages(join => ' / ', ok => 'All Health-Check are OK');
$plugin->nagios_exit($code, $message);
