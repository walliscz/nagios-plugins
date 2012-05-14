#!/usr/bin/perl

# $Id$

use strict;
use warnings;
use Nagios::Plugin;
use Data::Dumper;
use WWW::Mechanize::Timed;
use HTTP::Headers;
use HTTP::Request::Common qw(POST GET);
use HTTP::Status qw(:constants :is status_message);
use Switch;

# Definition des options
my $plugin = Nagios::Plugin->new(
	usage 	=> "Usage: %s -p <proxy> -l <Proxy_Port> [-o <Proxy_User>] [-m <Proxy_Pass>] -u <url> [-n <Url_User>] [-s <Url_Pass>] [-e <status>] [-r <regex>]",
	version => '0.3',
	blurb	=> 'Script to check website by proxy',
	plugin	=> 'check_website_by_proxy.pl',
	url	=> 'Created by Marc GUYARD <m.guyard@orange.com>',
	timeout	=> '15'
);

$plugin->add_arg(
	spec		=> 'proxy|p=s',
	help		=> "-p, --proxy=ADDRESS\n   Address of proxy",
	required	=> 1
);

$plugin->add_arg(
	spec		=> 'proxy-port|l=i',
	help		=> "-l, --port=INTEGER\n   Proxy Port",
	required	=> 1
);

$plugin->add_arg(
	spec		=> 'proxy-user|o=s',
	help		=> "-u, --proxy-user=STRING\n   Proxy Username",
	required	=> 0
);

$plugin->add_arg(
	spec		=> 'proxy-pass|m=s',
	help		=> "-m, --proxy-pass=STRING\n   Proxy Password",
	required	=> 0
);

$plugin->add_arg(
	spec		=> 'url|u=s',
	help		=> "-u, --url=STRING\n   Web URL to check (ex. http://www.google.com)",
	required	=> 1
);

$plugin->add_arg(
	spec		=> 'url-user|n=s',
	help		=> "-n, --url-user=STRING\n   Username if the web site required authentication",
	required	=> 0
);

$plugin->add_arg(
	spec		=> 'url-pass|s=s',
	help		=> "-s, --url-pass=STRING\n   Password if the web site required authentication",
	required	=> 0
);

$plugin->add_arg(
	spec		=> 'status|e=i',
	help		=> "-e, --status=INTEGER\n   HTTP code that should be returned (Default 200)",
	default		=> 200,
	required	=> 0
);

$plugin->add_arg(
	spec		=> 'regex|r=s',
	help		=> "-r, --regex=STRING\n   HTTP code that should be returned",
	required	=> 0
);

$plugin->add_arg(
	spec		=> 'warning|w=s',
	help		=> "-w, --warning=STRING\n   If the reply is superior to the value, a warning error is return (Default 3s)",
	default		=> 3,
	required	=> 0
);

$plugin->add_arg(
	spec		=> 'critical|c=s',
	help		=> "-c, --critical=STRING\n   If the reply is superior to the value, a critical error is return (Default 5s)",
	default		=> 5,
	required	=> 0
);

$plugin->getopts();
my $opts = $plugin->opts();

$SIG{ALRM} = sub {
	$plugin->nagios_exit(UNKNOWN, "Timeout reached");
};
alarm $opts->get('timeout');

# Recuperation des options
my $proxy			= $opts->get('proxy');
my $proxy_port		= $opts->get('proxy-port');
my $proxy_user		= $opts->get('proxy-user');
my $proxy_pass		= $opts->get('proxy-pass');
my $url				= $opts->get('url');
my $url_user		= $opts->get('url-user');
my $url_pass		= $opts->get('url-pass');
my $status			= $opts->get('status');
my $regex			= $opts->get('regex');
my $warning			= $opts->get('warning');
my $critical		= $opts->get('critical');
my $verbose			= $opts->get('verbose');

# Recuperation de la page
my $mech = WWW::Mechanize::Timed->new(
	agent => 'Supervision NSOC NIS' ,
	autocheck => 0
);
# Definition du proxy
$mech->proxy(['http', 'ftp'], "http://".$proxy.":".$proxy_port);
my $header = HTTP::Headers->new();

# Ajout des entetes de connexion proxy et website
$header->proxy_authorization_basic($proxy_user,$proxy_pass) if $proxy_user;
$header->authorization_basic($url_user, $url_pass) if $url_user;
# Desactive la compression de la reponse en GZIP
$header->header( 'Accept-Encoding' => 'identity'); 
my $request = HTTP::Request->new('GET', $url, $header);

# Appel de l'URL
my $threshold_status;
my $result = $mech->request($request);
print "Operation Result : ".$mech->success."\n" if $verbose;
print "Status Return : ".$result->status_line."\n" if $verbose;
print "Expected Status : ".$status."\n\n\n" if $verbose;
print "Content :\n\n".$result->content."\n\n" if $verbose;
# Verifie que le code HTTP n'est pas 5xx
if ( ! is_server_error($result->status_line) ) {
	# Verifie si le code de retour correspond a celui attendu
	if ($result->status_line =~ /^$status/) {
		# Une regex de test a etait saisi ?
		if ($regex) {
			# La regex est-elle presente dans la page retourne ?
			if ( $result->content =~ m/$regex/) {
				$plugin->add_message( OK, "Status: ".$result->status_line." and find '".$regex."' in return" );
			} else {
				# Le code de retour correspond mais la regex n'est pas trouve
				$plugin->add_message( CRITICAL, "Status: ".$result->status_line." but don't find string '".$regex."' in return" );
			}
		} else {
			# Le code de retour correspond
			$plugin->add_message( OK, "Status: ".$result->status_line );
		}
	} else {
		# Le code de retour ne correspond pas
		$plugin->add_message( CRITICAL, "Status: ".$result->status_line." but expected '".$status."'" );
	}
	# Threshold
	my $threshold = $plugin->set_thresholds(
		warning => $warning,
		critical => $critical,
	);
	$threshold_status = $threshold->get_status($mech->client_total_time);
	print "Threshold Status : ".$threshold_status."\n" if $verbose;
} else {
	$plugin->nagios_exit(CRITICAL, "Failed to retreive the URL '".$url."' (".$result->status_line.")");
}

# Debug Time
print "The time it took to connect to the remote server : ".$mech->client_request_connect_time."\n" if $verbose;
print "The time it took to transmit the request : ".$mech->client_request_transmit_time."\n" if $verbose;
print "Time it took to respond to the request : ".$mech->client_response_server_time."\n" if $verbose;
print "Time it took to get the data back : ".$mech->client_response_receive_time."\n" if $verbose;
print "Total Time : ".$mech->client_total_time."\n" if $verbose;

# Define threshold status
switch ($threshold_status) {
	case 1 { $plugin->add_message(WARNING, "-- Threshold (".$warning."s) excedeed - ".$mech->client_total_time."s"); }
	case 2 { $plugin->add_message(CRITICAL, "-- Threshold (".$critical."s) excedeed - ".$mech->client_total_time."s"); }
	case 3 { $plugin->add_message(UNKNOWN, "Unknown ERROR"); }
}

# Performance
$plugin->add_perfdata(
	label => "Total-Time",
	value => $mech->client_total_time,
	uom => "s",
	warning => $warning,
	critical => $critical,
);
$plugin->add_perfdata(
	label => "Request-Connect-Time",
	value => $mech->client_request_connect_time,
	uom => "s",
);
$plugin->add_perfdata(
	label => "Request-Transmit-Time",
	value => $mech->client_request_transmit_time,
	uom => "s",
);
$plugin->add_perfdata(
	label => "Response-Server-Time",
	value => $mech->client_response_server_time,
	uom => "s",
);
$plugin->add_perfdata(
	label => "Response-Receive-Time",
	value => $mech->client_response_receive_time,
	uom => "s",
);

# Retour des messages
my ($code, $message) = $plugin->check_messages();
$plugin->nagios_exit($code, $message);