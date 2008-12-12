package WGDev::Command;
use strict;
use warnings;

our $VERSION = '0.1.1';

use Getopt::Long ();
use File::Spec ();
use Cwd ();
use Carp qw(croak);

sub run {
    my $class = shift;
    Getopt::Long::Configure(qw(default gnu_getopt pass_through));
    Getopt::Long::GetOptionsFromArray(\@_,
        'h|?|help'          => \(my $opt_help),
        'V|ver|version'     => \(my $opt_version),

        'F|config-file=s'   => \(my $opt_config),
        'R|webgui-root=s'   => \(my $opt_root),
    ) || warn $class->usage && exit 1;

    $opt_config ||= $ENV{WEBGUI_CONFIG};
    $opt_root ||= $ENV{WEBGUI_ROOT};

    my $command_name = shift @_;

    my $command_module;
    if ($command_name && $command_name =~ /^[a-zA-Z0-9-]+$/) {
        (my $module = "WGDev::Command::\u$command_name") =~ s/-(.)/::\u$1/g;
        (my $module_file = "$module.pm") =~ s{::}{/}g;
        eval { require $module_file };
        if ( $module->can('run') ) {
            $command_module = $module;
        }
    }
    if ($command_name && !$command_module) {
        for my $path (File::Spec->path) {
            my $execpath = File::Spec->catfile($path, "wgd-$command_name");
            if (-x $execpath) {
                require WGDev;
                my $wgd = WGDev->new($opt_root, $opt_config);
                $wgd->set_environment;
                exec {$execpath} $execpath, $opt_help ? '--help' : (), $opt_version ? '--version' : (), @_;
            }
        }
    }

    if ($command_name && !$command_module) {
        warn $class->usage(message => "Can't find command $command_name!\n", include_cmd_list => 1);
        exit 2;
    }
    if ($opt_version) {
        print "WGDev::Command version $VERSION";
        if ($command_module) {
            print " - $command_module version " . $command_module->VERSION;
        }
        print "\n";
    }
    elsif ($opt_help) {
        if ($command_module) {
            if ($command_module->can('usage')) {
                print $command_module->usage;
            }
            else {
                warn "No documentation for $command_name command.\n"
            }
            exit;
        }
        else {
            print $class->usage;
            exit;
        }
    }
    elsif (!$command_name) {
        warn $class->usage(message => "No command specified!\n", include_cmd_list => 1);
        exit 1;
    }
    else {
        require WGDev;
        my $wgd = WGDev->new($opt_root, $opt_config);
        eval {
            $command_module->run($wgd, @_);
        };
        if ($@) {
            die $@;
        }
        exit;
    }
}

sub usage {
    my $class = shift;
    my %opts = @_;
    my $command_name = (File::Spec->splitpath($0))[2];
    my $message = $class . "\n";
    $message .= $opts{message}
        if $opts{message};
    $message .= <<"END_HELP";

usage: $command_name [arguments] <subcommand> [subcommand arguments]

arguments:
    -h
    -?
    --help          Display this help

    -V
    --version       Display version information

    -F
    --config-file=  Specify WebGUI config file to use.  Can be absolute, relative to
                    the current directory, or relative to WebGUI's config directory.
                    If not specified, it will try to use the WEBGUI_CONFIG environment
                    variable.  If that is not set and there is only one config file
                    in WebGUI's config directory, that file will be used.

    -R
    --webgui-root   Specify WebGUI's root directory.  Can be absolute or relative.
                    If not specified, first the WEBGUI_ROOT environment variable will
                    be checked, then will search upward from the current path for a
                    WebGUI installation.

END_HELP

    $message .= "subcommands available:\n";
    for my $command ($class->command_list) {
        $message .= "    $command\n";
    }
    $message .= "\n";
    return $message;
}

sub command_list {
    my $class = shift;
    my %commands;
    (my $fn_prefix = $class) =~ s{::}{/}g;

    require File::Find;
    for my $inc_path (@INC) {
        my $command_root = File::Spec->catdir($inc_path, split('::', $class));
        next
            unless -d $command_root;
        File::Find::find({
            no_chdir => 1,
            wanted => sub {
                return
                    unless /\.pm$/;
                no warnings;
                my $file = File::Spec->abs2rel($File::Find::name, $command_root);
                $file =~ s/\.pm$//;
                my $command = join('-', map {lcfirst} File::Spec->splitdir($file));
                $commands{$command} = 1;
            },
        }, $command_root);
    }
    for my $module ( grep { /^$fn_prefix\// } keys %INC ) {
        (my $command = $module) =~ s/\.pm$//;
        $command =~ s/^$fn_prefix\///;
        $command = join '-', map {lcfirst} split('/', $command);
        $commands{$command} = 1;
    }
    for my $command ( map { glob("$_/wgd-*") } File::Spec->path ) {
        next
            unless -x $command;
        my $file = (File::Spec->splitpath($command))[2];
        $file =~ s/^wgd-//;
        $commands{$file} = 1;
    }
    return sort keys %commands;
}

1;
