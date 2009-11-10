package Artemis::Installer;

use strict;
use warnings;

use Method::Signatures;
use Moose;
use Socket;
use YAML::Syck;

with 'MooseX::Log::Log4perl';

our $VERSION = '2.000057';

=head1 NAME

Artemis::Installer - Install everything needed for a test.

=head1 SYNOPSIS

 use Artemis::Installer;

=head1 FUNCTIONS

=cut

has cfg => (is      => 'rw',
            default => sub { {server=>undef, port => 1337} },
           );

method BUILD($config) 
{
        $self->{cfg}=$config;
};



=head2 mcp_inform

Tell the MCP server our current status. This is done using a TCP connection.

@param string - message to send to MCP

@return success - 0
@return error   - -1

=cut

method mcp_inform($msg)
{
        my $message = {state => $msg};
        return $self->mcp_send($message);
};



=head2 mcp_send

Tell the MCP server our current status. This is done using a TCP connection.

@param string - message to send to MCP

@return success - 0
@return error   - error string

=cut

sub mcp_send
{
        my ($self, $message) = @_;
        my $server = $self->cfg->{mcp_host} or return "MCP host unknown";
        my $port   = $self->cfg->{mcp_port} || 7357;

        my $yaml = Dump($message);
	if (my $sock = IO::Socket::INET->new(PeerAddr => $server,
					     PeerPort => $port,
					     Proto    => 'tcp')){
		print $sock ("$yaml");
		close $sock;
	} else {
                return("Can't connect to MCP: $!");
	}
        return(0);
}

=head2  logdie

Tell the MCP server our current status, then die().

@param string - message to send to MCP

=cut


method logdie($msg)
{
        if ($self->cfg->{mcp_host}) {
                $self->mcp_send({state => 'error-install', error => $msg});
        } else {
                $self->log->error("Can't inform MCP, no server is set");
        }
        die $msg;
};

1;

=head1 AUTHOR

OSRC SysInt Team, C<< <osrc-sysint at elbe.amd.com> >>

=head1 BUGS

None.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

 perldoc Artemis


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2008 OSRC SysInt Team, all rights reserved.

This program is released under the following license: restrictive


