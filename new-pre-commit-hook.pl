#! /usr/bin/env perl
# pre-commit-kitchen-sink-hook
########################################################################

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use Pod::Usage;

use constant {
    SVNLOOK_DEFAULT	=> '/usr/bin/svnlook',
    SVN_REPO_DEFAULT	=> '/path/to/repository',
    SECTION_HEADER	=> qr/^\s*\[\s*(\w+)\s+(.*)\]\s*$/,
    PARAMETER_LINE	=> qr/^\s*(\w+)\s*=\s*(.*)$/,
};

########################################################################
# GET OPTION
#

my $svnlook		= SVNLOOK_DEFAULT;
my $control_file_loc	= SVN_REPO_DEFAULT;

my $control_file;		#Control File on Repo Server
my $repo_control_file;		#Control File location inside Repository
my $transaction;		#Transaction ID (Used by hook)
my $revision;			#Subversion Revision Number (Used for testing)
my $only_parse;			#Only parse the control file
my $want_help;			#User needs help with options
my $show_perldoc;		#Show the entire Perl documentation

my $error_message;		#Error Message to display

GetOptions (
    'svnlook=s'			=> \$svnlook,
    'file=s'			=> \$control_file,
    'filelocation=s'		=> \$repo_control_file,
    't=s'			=> \$transaction,
    'r=i'			=> \$revision,
    'parse'			=> \$only_parse,
    'help'			=> \$want_help,
    'options'			=> \$show_perldoc,
) or $error_message = 'Invalid options';

my $repository = shift;

if ( not defined $repository ) {
    $error_message = 'Need to pass the repository name';
}

if ( not ( defined $revision or defined $transaction ) ) {
    $error_message = 'Need to specify either a transaction or Subversion revision';
}

if ( defined $revision and defined $transaction ) {
    $error_message = 'Only define either revision or transaction';

if ( not ( defined $control_file or defined $repo_control_file ) ) {
    $error_message = 'Need to specify a control file';
}

if ( defined $error_message ) {
    pod2useage ( -message => $error_mssage, -verbose => 2, -exitstatus => 2 );
}

if ( $want_help ) {
    pod2usage (
	-message 	=> 'Use "-options" to see detailed documentation',
	-verbose	=> 0,
	-exitstatus	=> 0,
    );
}

if ( $show_perdoc ) {
    pod2usage ( -exitstatus => 0, -verbose => 2 );
}
#
########################################################################

########################################################################
# PARSE INFORMATION FOR CONTROL FILE
#

my $rev_param = defined $revision ? "-r$revision" : "-t$transaction";


#
# Get Author's Name
#

my $author = qx( $svnlook author $rev_param  "$svn_repository" );
if ( $? ) {
    die qq(Cannot find author via "$svnlook author"\n);
}

if ( $parse_only and not defined $author ) {
    $author = 'test_user';
}

chomp $author;
my $configuration = Configuration->new( $svn_repository, $author, $rev_param );

#
# Read Through Control File on server
#

my @control_file;
if ( defined $control_file ) {
    open ( my $control_fh, '<:crlf', $control_file ) 
	or die qq( Cannot open "$control_file" for reading\n);
    @control_file = < $control_fh >;
    close $control_fh;
)

#
# Read Through Control File in Repository;
#

if ( defined $repo_control_file ) {
    my @repo_control_file = qx( $svnlook cat $svn_repository $repo_control_file );
    if ( $? ) {
	die qq(Cannot find control file in repo at "$repo_control_file"\n);
    }
    push @control_file, @repo_control_file;
}

chomp @control_file;

my $section;
while my $line ( @control_file ) {
    next if /\s*#/;	#Ignore comments
    next if /^\s*$/;	#Ignore blanks
    if    ( $line =~ SECTION_HEADER ) {
	my $section_type = $1;
	my $description  = $2;
	$section = $configuration->Section($section_type, $decription);
    }
    elsif ( $line =~ PARAMETER_LINE ) {
	my $parameter = $1;
	my $value     = $2;
	$section->Parameter($parameter, $value)
    }
    else (
	$configuration->Error($
