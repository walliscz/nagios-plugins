#!/usr/bin/perl

# $Id$

use strict;
use warnings;
use Nagios::Plugin;
use WWW::Mechanize;
use Crypt::SSLeay;
use XML::Simple qw(:strict);
use Data::Dumper;

my $plugin = Nagios::Plugin->new(
	usage 	=> "Usage: %s -H <host> -T <TestId> -a <application-id> [-P <path>] [-p <http_port>] [-S]",
	version => '0.3',
	blurb	=> 'Script to check racvision XML',
	plugin	=> 'check_racvision',
	url		=> 'Created by Marc GUYARD <m.guyard@orange-ftgroup.com>',
	timeout	=> '15'
);
my $mech = WWW::Mechanize->new(
	agent 	=> 'Supervision NIS',
	autocheck => 0
);

$plugin->add_arg(
	spec		=> 'host|H=s',
	help		=> "-H, --host=ADDRESS\n   Web Server Address",
	required	=> 1
);

$plugin->add_arg(
	spec		=> 'path|P=s',
	help		=> "-P, --path=STRING\n   Racvision XML page path",
	default		=> '/'
);

$plugin->add_arg(
	spec		=> 'port|p=i',
	help		=> "-p, --port=INTEGER\n   Webserver port",
	default		=> '80'
);

$plugin->add_arg(
	spec		=> 'ssl|S',
	help		=> "-S, --ssl\n   Use HTTPS Address"
);

$plugin->add_arg(
	spec            => 'testid|T=s',
	help            => "-T, --testid=STRING\n	Specify TestID to verify (separate multi value by a coma)",
	required        => 1
);

$plugin->add_arg(
	spec            => 'application|a=s',
	help            => "-a, --application=STRING\n	Specify the Application ID (look in XML to find it",
	required        => 1
);

$plugin->getopts();
my $opts = $plugin->opts();

$SIG{ALRM} = sub {
	$plugin->nagios_exit(UNKNOWN, "Timeout reached");
};
alarm $opts->get('timeout');


my $host	= $opts->get('host');
my $path	= $opts->get('path');
my $port	= $opts->get('port');
my $ssl		= $opts->get('ssl');
my @tab_testid	= $opts->get('testid');
my $application	= $opts->get('application');
my $timeout	= $opts->get('timeout');
my $verbose	= $opts->get('verbose');
@tab_testid = split(/,/,join(',',@tab_testid));



# Forge URL
#################
my $url;
my $http_type = "http";

if ( $ssl ) {
	$http_type = "https";
	$port = "443" unless $port;
} 

$url = $http_type."://".$host.":".$port.$path;
print "DEBUG :: Url = ".$url."\n" if $verbose;
$mech->get( $url );
$mech->success or $plugin->nagios_exit(UNKNOWN, "No response from server (".$url.")");
my $source = $mech->content;
print "DEBUG :: \nSource HTML : \n".$source."\n\n\n" if $verbose;



# Parse XML
################

my $xml = new XML::Simple;
my $data = $xml->XMLin( $source , forcearray => 1 , KeyAttr => ['id'] , suppressempty => '' );
print "XML Dump\n****************\n".Dumper($data)."\n\n\n" if $verbose ;

foreach my $testid (@tab_testid) {
	print "DEBUG :: TestID => ".$testid."\n" if $verbose;
	print "DEBUG :: Value => ".$data->{application}->{$application}->{test}->{$testid}->{state}->[0]->{val}."\n" if $verbose;
	if ( $data->{application}->{$application}->{test}->{$testid}->{result}->[0] ) {
		print "DEBUG :: Result => $data->{application}->{$application}->{test}->{$testid}->{result}->[0]\n" if $verbose;
	} else {
		print "DEBUG :: Result => No result available\n" if $verbose;
	}
	my $result = $data->{application}->{$application}->{test}->{$testid}->{state}->[0]->{val};
	my $description_testid = $data->{application}->{$application}->{test}->{$testid}->{description}->[0];
	if ( $result !~ /OK/ ) {
		my $result_fail = "No result available";
		if ( $data->{application}->{$application}->{test}->{$testid}->{result}->[0] ) {
			$result_fail = $data->{application}->{$application}->{test}->{$testid}->{result}->[0];
		}
		$plugin->add_message(CRITICAL, "$testid ($result_fail)");
	} else {
		$plugin->add_message(OK, "Test ".$testid." OK");
	}
}

my ($code, $message) = $plugin->check_messages();
$message = "All test are valid" if $code == 0;
$plugin->nagios_exit($code, $message);
