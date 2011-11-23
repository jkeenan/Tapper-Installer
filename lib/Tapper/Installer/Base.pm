package Tapper::Installer::Base;

use Moose;

use common::sense;

use Tapper::Remote::Config;
use Tapper::Installer::Precondition::Copyfile;
use Tapper::Installer::Precondition::Exec;
use Tapper::Installer::Precondition::Fstab;
use Tapper::Installer::Precondition::Image;
use Tapper::Installer::Precondition::Kernelbuild;
use Tapper::Installer::Precondition::PRC;
use Tapper::Installer::Precondition::Package;
use Tapper::Installer::Precondition::Rawimage;
use Tapper::Installer::Precondition::Repository;
use Tapper::Installer::Precondition::Simnow;

extends 'Tapper::Installer';

=head1 NAME

Tapper::Installer::Base - Install everything needed for a test.

=head1 SYNOPSIS

 use Tapper::Installer::Base;

=head1 FUNCTIONS

=cut

=head2 free_loop_device

Make sure /dev/loop0 is usable for losetup and kpartx.

@return success - 0
@return error   - error string

=cut

sub free_loop_device
{
        my ($self) = @_;
        my ($error, $dev) = $self->log_and_exec('losetup', '-f');

        return if !$error and $dev eq '/dev/loop0';
        ($error, $dev) = $self->log_and_exec("mount | grep loop0 | cut -f 3 -d ' '");
        return $dev if $error; # can not search for mounts

        if ($dev) {
                $error = $self->log_and_exec("umount $dev");
                if ($error) {
                        my $processes;
                        ($error, $processes) =
                          $self->log_and_exec('lsof -t +D $dev 2>/dev/null');
                        foreach my $proc (split "\n", $processes) {
                                kill 15, $proc;
                                sleep 2;
                                kill 9, $proc;
                        }
                        $error = $self->log_and_exec("umount $dev");
                        return $error if $error;
                }
        }

        ($error, $dev) = $self->log_and_exec("kpartx -d /dev/loop0");
        return $dev if $error;

        ($error, $dev) = $self->log_and_exec("losetup -d /dev/loop0");
        return;
}

=head2 cleanup

Clean a set of predefine file by deleting all of their content. This prevents
confusion in certain test suites which could occur when they find old content
in log files. Only warns on error.

@return success - 0

=cut

sub cleanup
{
        my ($self) = @_;

        $self->log->info('Cleaning up logfiles');
        my @files_to_clean = ('/var/log/messages','/var/log/syslog');
 FILE:
        foreach my $file (@files_to_clean) {
                my $filename = $self->cfg->{paths}{base_dir}."$file";
                next FILE if not -e $filename;
                open my $fh, ">", $filename or $self->log->warn("Can not open $filename for cleaning: $!"), next FILE;
                print $fh '';
                close $fh;
        }
        return 0;
}



=head2 system_install

Install whatever has to be installed. This function is a wrapper around all
other system installer functions and calls them appropriately. Note that the
function will not return in case of an error. Instead it throws an exception with
should be send to the server by Log4perl.

@param string - in what state are we called (autoinstall, other)

=cut

sub system_install
{
        my ($self, $state) = @_;

        my $retval;
        $state ||= 'standard';  # always defined value for state
        # fetch configurations from the server
        my $consumer = Tapper::Remote::Config->new;

        my $config=$consumer->get_local_data('install');
        $self->logdie($config) if not ref($config) eq 'HASH';

        $self->{cfg}=$config;
        $self->logdie("can't get local data: $config") if ref $config ne "HASH";

        if (not $state eq 'simnow') {
                $retval = $self->nfs_mount();
                $self->log->warn($retval) if $retval;
        }

        $self->log->info("Installing testrun (".$self->cfg->{testrun_id}.") on host ".$self->cfg->{hostname});
        $self->mcp_inform("start-install") unless $state eq "autoinstall";

        if ($state eq 'simnow') {
                $retval = $self->free_loop_device();
                $self->logdie($retval) if $retval;
        }

        my $image=Tapper::Installer::Precondition::Image->new($config);
        if ($state eq "standard") {
                $self->logdie("First precondition is not the root image")
                  if not $config->{preconditions}->[0]->{precondition_type} eq 'image'
                    and $config->{preconditions}->[0]->{mount} eq '/';
        }

        foreach my $precondition (@{$config->{preconditions}}) {
                if ($precondition->{precondition_type} eq 'image')
                {
                        $retval = $image->precondition_install($precondition);
                }
                elsif ($precondition->{precondition_type} eq 'package')
                {
                        my $package=Tapper::Installer::Precondition::Package->new($config);
                        $retval = $package->precondition_install($precondition);
                }
                elsif ($precondition->{precondition_type} eq 'copyfile')
                {
                        my $copyfile = Tapper::Installer::Precondition::Copyfile->new($config);
                        $retval = $copyfile->precondition_install($precondition);
                }
                elsif ($precondition->{precondition_type} eq 'fstab')
                {
                        my $fstab = Tapper::Installer::Precondition::Fstab->new($config);
                        $retval = $fstab->precondition_install($precondition);
                }
                elsif ($precondition->{precondition_type} eq 'prc')
                {
                        my $prc=Tapper::Installer::Precondition::PRC->new($config);
                        $retval = $prc->precondition_install($precondition);
                }
                elsif ($precondition->{precondition_type} eq 'rawimage')
                {
                        my $rawimage=Tapper::Installer::Precondition::Rawimage->new($config);
                        $retval = $rawimage->precondition_install($precondition);
                }
                elsif ($precondition->{precondition_type} eq 'repository')
                {
                        my $repository=Tapper::Installer::Precondition::Repository->new($config);
                        $retval = $repository->precondition_install($precondition);
                }
                elsif ($precondition->{precondition_type} eq 'exec')
                {
                        my $exec=Tapper::Installer::Precondition::Exec->new($config);
                        $retval = $exec->precondition_install($precondition);
                }
                elsif ($precondition->{precondition_type} eq 'simnow_backend')
                {
                        my $simnow=Tapper::Installer::Precondition::Simnow->new($config);
                        $retval = $simnow->precondition_install($precondition);
                }
                elsif ($precondition->{precondition_type} eq 'kernelbuild')
                {
                        my $kernelbuild=Tapper::Installer::Precondition::Kernelbuild->new($config);
                        $retval = $kernelbuild->precondition_install($precondition);
                }

                if ($retval) {
                        if ($precondition->{continue_on_error}) {
                                $self->mcp_send({state => 'warn-install', error => $retval});
                        } else {
                                $self->logdie($retval);
                        }
                }
        }

        $self->cleanup() unless $config->{no_cleanup} or $state eq 'simnow' or $state eq 'ssh';

        if ( $state eq "standard" and  not ($config->{skip_prepare_boot})) {
                $self->logdie($retval) if $retval = $image->prepare_boot();

        }
        $image->unmount();

        $self->mcp_inform("end-install");
        $self->log->info("Finished installation of test machine");

        given ($state){
                when ("standard"){
                        return 0 if $config->{installer_stop};
                        system("reboot");
                }
                when ('simnow'){
                        #FIXME: don't use hardcoded path
                        my $simnow_config = $self->cfg->{files}{simnow_config};
                        $retval = qx(/opt/tapper/bin/perl /opt/tapper/bin/tapper-simnow-start --config=$simnow_config);
                        if ($?) {
                                $self->log->error("Can not start simnow: $retval");
                                $self->mcp_send({state => 'error-test',
                                                 error => "Can not start simnow: $retval",
                                                 prc_number => 0});
                        }
;
                }
        }
        return 0;
}


1;

=head1 AUTHOR

AMD OSRC Tapper Team, C<< <tapper at amd64.org> >>

=head1 BUGS

None.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

 perldoc Tapper


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2008-2011 AMD OSRC Tapper Team, all rights reserved.

This program is released under the following license: freebsd


