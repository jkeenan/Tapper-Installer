package Tapper::Installer::Precondition::Package;

use strict;
use warnings;
use 5.010;

use Tapper::Installer::Precondition::Exec;
use File::Basename;
use Moose;
extends 'Tapper::Installer::Precondition';


=head1 NAME

Tapper::Installer::Precondition::Package - Install a package to a given location

=head1 SYNOPSIS

 use Tapper::Installer::Precondition::Package;

=head1 FUNCTIONS

=cut


=head2 install

This function encapsulates installing one single package. At the moment, .tar,
.tar.gz, .tar.bz2, rpm and deb are recognised.
Recognised options for package preconditions are:
* filename         - absolute or relative path of the package file (relativ to package_dir in config)
* target_directory - directory where to unpack package
*


@param hash reference - contains all information about the package

@return success - 0
@return error   - error string

=cut

sub install
{
        my ($self, $package) = @_;
        if ($package->{url}) {
                my ($proto, $fullpath) = $package->{url} =~ m|^(\w+)://(.+)$|;
                given($proto) {
                        when ('nfs') {
                                my $nfs_dir='/mnt/nfs';
                                my $path = dirname $fullpath;
                                my $filename = basename $fullpath;
                                my ($error, $retval) = $self->log_and_exec("mount $path $nfs_dir");
                                return ("Can't mount nfs share $path to $nfs_dir: $retval") if $error;
                                delete $package->{url};
                                $package->{filename} = "$nfs_dir/$filename";
                                $self->install($package);
                                ($error, $retval) = $self->log_and_exec("umount $nfs_dir");
                                return 0;
                        }
                        default { return ("Procol'$proto' is not supported") }
                }
        }


        my $filename = $package->{filename};
	$self->log->debug("installing $filename");

        my $basedir     = $self->cfg->{paths}{base_dir};

        # install into subdir
        if ($package->{target_directory}) {
                $basedir       .= $package->{target_directory};
                $self->makedir($basedir) if not -d $basedir;
        }

        my $package_dir = '';
        $package_dir    = $self->cfg->{paths}{package_dir};
        my $pkg = $filename;
        $pkg = "$package_dir/$filename" unless $filename =~ m(^/);

        my ($error, $type) = $self->get_file_type("$pkg");
        return("Can't get file type of $filename: $type") if $error;


        my $output;
        $self->log->debug("type is $type");
        given($type){
                when("gzip") {
                        ($error, $output) = $self->log_and_exec("tar --no-same-owner -C $basedir -xzf $pkg");
                        return("can't unpack package $filename: $output\n") if $error;
                }
                when("tar") {
                        ($error, $output) = $self->log_and_exec("tar --no-same-owner -C $basedir -xf $pkg");
                        return("can't unpack package $filename: $output\n") if $error;
                }
                when("bz2") {
                        ($error, $output) = $self->log_and_exec("tar --no-same-owner -C $basedir -xjf $pkg");
                        return("can't unpack package $filename: $output\n") if $error;
                }
                when("deb") {
                        system("cp $pkg $basedir/");
                        $pkg = basename $pkg;
                        my $exec = Tapper::Installer::Precondition::Exec->new($self->cfg);
                        return $exec->install({command => "dpkg -i $pkg"});
                }
                when("rpm") {
                        system("cp $pkg $basedir/");
                        $pkg = basename $pkg;
                        my $exec = Tapper::Installer::Precondition::Exec->new($self->cfg);
                        # use -U to overwrite possibly existing	older package
                        return $exec->install({command => "rpm -U  $pkg"});
                }
                default{
                        $self->log->warn(qq($pkg is of unrecognised file type "$type"));
                        return(qq($pkg is of unrecognised file type "$type"));
                }
        }
        return(0);
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
