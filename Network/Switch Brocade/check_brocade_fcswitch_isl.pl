#!/usr/bin/perl -w
#
#############################################################
# Copyright or © or Copr. Anthony FOIGNANT
#
# antispameu-nagios@yahoo.fr
#
# This software is a computer program whose purpose is to CHECK THE ISL
# STATE OF A BROCADE SWITCH AND RETURN IT TO NAGIOS
# 
# This software is governed by the CeCILL license under French law and
# abiding by the rules of distribution of free software.  You can  use, 
# modify and/ or redistribute the software under the terms of the CeCILL
# license as circulated by CEA, CNRS and INRIA at the following URL
# "http://www.cecill.info". 
#
# As a counterpart to the access to the source code and  rights to copy,
# modify and redistribute granted by the license, users are provided only
# with a limited warranty  and the software's author,  the holder of the
# economic rights,  and the successive licensors  have only  limited
# liability. 
# 
# In this respect, the user's attention is drawn to the risks associated
# with loading,  using,  modifying and/or developing or reproducing the
# software by the user in light of its specific status of free software,
# that may mean  that it is complicated to manipulate,  and  that  also
# therefore means  that it is reserved for developers  and  experienced
# professionals having in-depth computer knowledge. Users are therefore
# encouraged to load and test the software's suitability as regards their
# requirements in conditions enabling the security of their systems and/or 
# data to be ensured and,  more generally, to use and operate it in the 
# same conditions as regards security. 
# 
# The fact that you are presently reading this means that you have had
# knowledge of the CeCILL license and that you accept its terms.
#
##########################################################
#
# Date : 03/09/2008
# check_snmp_isl_brocade.pl
#
# supported types: Silkworm4900, Connectrix DS-4900B
#
###########################################################
#
# CHANGELOG :
# 1.0 : initial release
# 1.1 : Bug correction on the hostname's verification (Thanks to Sebastian Mueller :)
# 1.2 : Changing the verification of the type of the switch so it could work for a lot of brocade switch
##########################################################

#global variables:
use strict;
use SNMP;
use lib "/usr/local/nagios/libexec";
use utils qw($TIMEOUT %ERRORS &print_revision &support);
use vars qw($PROGNAME);
use Getopt::Long;
use vars qw($opt_h $opt_H $opt_C);
my ( $IP,         $COMMUNITY, 	$SNMP_VERSION );
my ( $NB_WARNING, $MSG, $type );
my ( $isl_number, $isl, $isl_status, $isl_port, $isl_port_oper_status, $sess );

$PROGNAME = "check_brocade_fcswitch_isl";
$SNMP_VERSION = 1;
sub print_help ();
sub print_usage ();

# options definitions
Getopt::Long::Configure('bundling');
GetOptions(
            "h"           => \$opt_h,
            "help"        => \$opt_h,
            "H=s"         => \$opt_H,
            "hostname=s"  => \$opt_H,
            "C=s"         => \$opt_C,
            "community=s" => \$opt_C,
	    "v=s"	  => \$SNMP_VERSION,
);

if ($opt_h) {
    print_help();
    exit $ERRORS{OK};
}

# verify the options

$opt_H = shift unless ($opt_H);
print_usage() unless ($opt_H);

# the help :-)
sub print_usage () {
    print "Usage: $PROGNAME -H <host> -C SNMPv1community\n";
    exit(3);
}

sub print_help () {
    print "\n";
    print_usage();
    print "\n";
    print
"The script verify the state of each ISL of a Brocade Connectrix DS. It checks if each ISL is activated and the isl port is online.\n";
    print "-H = IP of the host.\n";
    print "-C = SNMP v1 community string.\n\n";
    support();
}

# verification of parameters of the script
$IP = $1
  if ( $opt_H =~
m/^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+|[a-zA-Z][-a-zA-Z0-9]+(\.[a-zA-Z][-a-zA-Z0-9]+)*)$/
  );
print_usage() unless ($IP);
$COMMUNITY = $opt_C;
print_usage() unless ($COMMUNITY);

# a variable in order to count the number of faults.
$NB_WARNING = 0;

# initialisation of the variable that contain the message
$MSG = "";

# Ajout EHE 2011.02.04 - support v2c
if($SNMP_VERSION =~ /^2c$/) {
        $SNMP_VERSION = 2;
}


# try to get the type of switch. if it doesn't work, it may be an error in the IP or the Community string
$sess =
  new SNMP::Session( DestHost => $IP, Community => $COMMUNITY, Version => $SNMP_VERSION )
  or die
"Unable to connect to $IP ! Please verify the IP or the community string : $COMMUNITY.\n";
$type = $sess->get('.1.3.6.1.2.1.1.1.0');
if ($type) {
	&verify_isl;
}
else {
    print
"ISL UNKNOWN : No response from the switch $IP ! Please verify the IP or the community string : $COMMUNITY.\n";
    exit $ERRORS{UNKNOWN};
}

##function to verify the isl
sub verify_isl {

    #get the number of isl links
    $isl_number = $sess->get('.1.3.6.1.4.1.1588.2.1.1.1.2.8.0');
    if ($isl_number) {
        $isl_number =~ s/^(.*)(INTEGER: )+(.*)$/$3/g;
        $isl_number =~ s/\"//g;
        if ( $isl_number == 0 ) {
            print "ISL UNKNOWN : There is no ISL configurate on $IP!\n";
            exit $ERRORS{UNKNOWN};
        }
    }
    else {
        print "ISL UNKNOWN : No response for the number of ISL of $IP!\n";
        exit $ERRORS{UNKNOWN};
    }

    # for an isl, get the port number, and status
    for ( $isl = 1 ; $isl <= $isl_number ; $isl++ ) {

        $isl_port = $sess->get(".1.3.6.1.4.1.1588.2.1.1.1.2.9.1.2.$isl");
        $isl_port =~ s/^(.*)(INTEGER: )+(.*)$/$3/g;
        $isl_port =~ s/\"//g;

        $isl_status = $sess->get(".1.3.6.1.4.1.1588.2.1.1.1.2.9.1.6.$isl");
        $isl_status =~ s/^(.*)(INTEGER: )+(.*)$/$3/g;
        $isl_status =~ s/\"//g;

        # verify that the isl is active (5)
        # # status results:
        # 1 sw-init
        # 2 sw-internal2
        # 3 sw-internal3
        # 4 sw-internal4
        # 5 sw-active
        if ( $isl_status != 5 ) {

# the FC port begins at zero, so we have to decrement the number of the port that we report
            $MSG = sprintf( "%sISL on port %d is admin DOWN ! ",
                            $MSG, $isl_port - 1 );
        }
        else {
            $MSG =
              sprintf( "%sISL on port %d is admin up. ", $MSG, $isl_port - 1 );
        }

        # Then check that the isl port is online and enable
        $isl_port_oper_status =
          $sess->get(".1.3.6.1.4.1.1588.2.1.1.1.6.2.1.4.$isl_port");
        $isl_port_oper_status =~ s/^(.*)(INTEGER: )+(.*)$/$3/g;
        $isl_port_oper_status =~ s/\"//g;

        # verify that the isl port is online (1)
        # # status results:
        # 0 unknown
        # 1 online
        # 2 offline
        # 3 testing
        # 4 faulty
        if ( $isl_port_oper_status != 1 ) {
            $NB_WARNING++;
            $MSG =
              sprintf( "%sbut is not operationnal ! ", $MSG, $isl_port - 1 );
        }
        else {
            $MSG = sprintf( "%sand is operationnal. ", $MSG );
        }

    }
}

## function to verify the status

if ($NB_WARNING) {
    if ( $NB_WARNING >= $isl_number ) {
        print
"ISL CRITICAL : The ISL status on switch $IP is NOT HEALTHY. $MSG To check the switch go to: http://$IP\n";
        exit $ERRORS{CRITICAL};
    }
    else {
        print
"ISL WARNING : The ISL status on switch $IP is NOT HEALTHY. $MSG To check the switch go to: http://$IP\n";
        exit $ERRORS{WARNING};
    }
}
else {
    print "ISL OK : ISL status on switch $IP is HEALTHY. $MSG\n";
    exit $ERRORS{OK};
}
