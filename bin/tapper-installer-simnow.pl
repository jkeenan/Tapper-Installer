#!/opt/tapper/bin/perl

use warnings;
use strict;
use Log::Log4perl;
use Daemon::Daemonize qw/:all/;

use Tapper::Installer::Base;

BEGIN {
	Log::Log4perl::init('/etc/log4perl.cfg');
}

# don't use the config of the last simnow session
system("rm","/etc/tapper") if -e "/etc/tapper";


Daemon::Daemonize->daemonize(close => "std");


my $client = new Tapper::Installer::Base;
$client->system_install("simnow");




=pod

=head1 NAME

tapper-installer-client.pl - control the installation and setup of an automatic test system

=head1 SYNOPSIS

tapper-installer-client.pl 

=head1 DESCRIPTION

This program is the start script of the Tapper::Installer project. It calls
Tapper::Installer::Base which cares for the rest.

=cut
