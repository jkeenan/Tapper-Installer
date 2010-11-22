package Artemis::Installer::Precondition::PRC;

use strict;
use warnings;

use File::Basename;
use Hash::Merge::Simple 'merge';
use File::ShareDir      'module_file';
use Moose;
use YAML;
extends 'Artemis::Installer::Precondition';


=head1 NAME

Artemis::Installer::Precondition::PRC - Install Program Run Control to a given location

=head1 SYNOPSIS

 use Artemis::Installer::Precondition::PRC;

=head1 FUNCTIONS

=cut

=head2 create_common_config

Create the part of the config that is the same for both Windows and Unix.

@return hash ref

=cut

sub create_common_config
{
        my ($self, $config) = @_;
        $config->{report_server}   = $self->{cfg}->{report_server};
        $config->{report_port}     = $self->{cfg}->{report_port};
        $config->{report_api_port} = $self->{cfg}->{report_api_port};
        $config->{hostname}        = $self->{cfg}->{hostname};  # allows guest systems to know their host system name
        $config->{test_run}        = $self->{cfg}->{test_run};
        $config->{mcp_port}        = $self->{cfg}->{mcp_port} if $self->{cfg}->{mcp_port};
        $config->{mcp_server}      = $self->{cfg}->{mcp_server};
        $config->{sync_port}       = $self->{cfg}->{sync_port} if $self->{cfg}->{sync_port};
        $config->{prc_nfs_server}  = $self->{cfg}->{prc_nfs_server} if $self->{cfg}->{prc_nfs_server}; # prc_nfs_path is set by merging paths above
        $config->{scenario_id}     = $self->{cfg}->{scenario_id} if $self->{cfg}->{scenario_id};
        $config->{paths}           = $self->{cfg}->{paths};
        $config->{files}           = $self->{cfg}->{files} if $self->{cfg}->{files} ;
        return $config;
}

=head2 create_config

Generate a config for PRC. Take special care for virtualisation
environments. In this case, the host system runs a proxy which collects status
messages from all virtualisation guests.

@param hash reference - contains all information about the PRC to install

@return success - (0, config hash)
@return error   - (1, error string)

=cut

sub create_config
{
        my ($self, $prc) = @_;
        my $config = $self->create_common_config($prc->{config});
        $config    = merge($config, {times=>$self->{cfg}->{times}});
        my @timeouts;

        if ($prc->{config}->{guest_count})
        {
                $config->{guest_count} = $prc->{config}->{guest_count};
                $config->{timeouts}    = $prc->{config}->{timeouts};
        }
        else
        {
                $config->{mcp_server}      = $self->{cfg}->{mcp_server};
        }
        

        return (0, $config);
}


=head2 install_startscript

Install a startscript for init in test state.

@return success - 0
@return error   - error string

=cut

sub install_startscript
{
        my ($self, $distro) = @_;
        my $basedir = $self->cfg->{paths}{base_dir};
        my ($error, $retval);
        if (not -d "$basedir/etc/init.d" ) {
                mkdir("$basedir/etc/init.d") or return "Can't create /etc/init.d/ in $basedir";
        }
        ($error, $retval) = $self->log_and_exec("cp",module_file('Artemis::Installer', "startfiles/$distro/etc/init.d/artemis"),"$basedir/etc/init.d/artemis");
        return $retval if $error;
        if ($distro!~/artemis/) {
        
                pipe (my $read, my $write);
                return ("Can't open pipe:$!") if not (defined $read and defined $write);

                # fork for the stuff inside chroot
                my $pid     = fork();
                return "fork failed: $!" if not defined $pid;
	
                # child
                if ($pid == 0) {
                        close $read;
                        chroot $basedir;
                        chdir ("/");
		
                        my $ret = 0;
                        my ($error, $retval);
                        if ($distro=~m/suse/) {
                                ($error, $retval)=$self->log_and_exec("insserv","/etc/init.d/artemis");
                        } elsif ($distro=~m/(redhat)|(fedora)/) {
                                ($error, $retval)=$self->log_and_exec("chkconfig","--add","artemis"); 
                        } elsif ($distro=~/gentoo/) {
                                ($error, $retval)=$self->log_and_exec("rc-update", "add", "artemis_gentoo", "default");
                        } else {
                                ($error, $retval)=(1,"No supported distribution detected.");
                        }
                        print($write "$retval") if $error;
                        close $write;
                        exit $error;
                } else {        # parent
                        close $write;
                        waitpid($pid,0);
                        if ($?) {
                                my $output = <$read>;
                                return($output);
                        }
                }
        }
}

=head2 create_win_config

Create the config for a windows guest running the special Win-PRC. Win-PRC
expects a flat YAML with some different keys and does not want any waste
options. 

@param hash reference - contains all information about the PRC to install

@return success - (0, config hash)
@return error   - (1, error string)

=cut

sub create_win_config
{
        my ($self, $prc) = @_;
        my $config = $self->create_common_config();
        $config->{guest_number} = $prc->{config}->{guest_number} if $prc->{config}->{guest_number};

        if ($prc->{config}->{guest_count})
        {
                $config->{guest_count} = $prc->{config}->{guest_count};
        }
        if ($prc->{config}->{testprogram_list}) {
                for (my $i=0; $i< int @{$prc->{config}->{testprogram_list}}; $i++) {
                        # string concatenation for hash keys, otherwise perl can't tell whether
                        # $i ot $i_prog is the name of the variable
                        my $list_element = $prc->{config}->{testprogram_list}->[$i];
                        $config->{"test".$i."_prog"}            = $list_element->{program};
                        $config->{"test".$i."_prog"}          ||= $list_element->{test_program};
                        $config->{"test".$i."_runtime_default"} = $list_element->{runtime};
                        $config->{"test".$i."_timeout"}         = $list_element->{timeout};
                        $config->{"test".$i."_timeout"}       ||= $list_element->{timeout_testprogram};
                }
        } elsif ($prc->{config}->{test_program}) {
                $config->{test0_prog}            = $prc->{config}->{test_program};
                $config->{test0_runtime_default} = $prc->{config}->{runtime};
                $config->{test0_timeout}         = $prc->{config}->{timeout_testprogram}
        }
        
        return (0, $config);
        
}


=head2 install

Install the tools used to control running of programs on the test
system. This function is implemented to fullfill the needs of kernel
testing and is likely to change dramatically in the future due to
limited extensibility. Furthermore, it has the name of the PRC hard
coded which isn't a good thing either.

@param hash ref - contains all information about the PRC to install

@return success - 0
@return error   - return value of system or error string

=cut

sub install
{
        my ($self, $prc) = @_;

        my $basedir = $self->cfg->{paths}{base_dir};
        my ($error, $retval);
        my $distro = $self->get_distro($basedir);
        $retval    = $self->install_startscript($distro) if $distro and not $distro eq 'Debian';
        return $retval if $retval;

        my $config;
        ($error, $config) = $self->create_config($prc);
        return $config if $error;

        $self->makedir("$basedir/etc") if not -d "$basedir/etc";

        open my $FILE, '>',"$basedir/etc/artemis" or return "Can not open /etc/artemis in $basedir:$!";
        print $FILE YAML::Dump($config);
        close $FILE;

        ($error, $config) = $self->create_win_config($prc);
        return $config if $error;

        open $FILE, '>', $basedir.'/test.config' or return "Can not open /test.config in $basedir:$!";
        print $FILE YAML::Dump($config);
        close $FILE;


        
        if ($prc->{artemis_package}) {
                my $pkg_object=Artemis::Installer::Precondition::Package->new($self->cfg);
                my $package={filename => $prc->{artemis_package}};
                $self->logdie($retval) if $retval = $pkg_object->install($package);
        }

        return 0;
}



=head2 get_distro

Find out which distribution is installed below the directory structure
given as argument. The guessed distribution is returned as a string.

@param string - path name under which to check for an installed
distribution

@return success - name of the distro
@return error   - empty string

=cut

sub get_distro
{
        my ($self, $dir) = @_;
	my @files=glob("$dir/etc/*-release");
	for my $file(@files){
		return "suse"    if $file  =~ /suse/i;
		return "redhat"  if $file  =~ /redhat/i;
		return "gentoo"  if $file  =~ /gentoo/i;
		return "artemis" if $file  =~ /artemis/i;
	}
        {
                open my $fh, '<',"$dir/etc/issue" or next;
                local $\='';
                my $issue = <$fh>;
                close $fh;
                my $distro;
                ($distro) = $issue =~ m/(Debian)/;
                return $distro if $distro;
        }
	return "";
}


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
