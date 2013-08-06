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

use constant { 		#Control File Type (package Control)
    FILE_IN_REPO	=> "R",
    FILE_ON_SERVER	=> "F",
};

use constant {		#Revision file Type (package Configuration)
    TRANSACTION 	=> "T",
    REVISION		=> "R",
};

########################################################################
# GET OPTION
#

my $svnlook			= SVNLOOK_DEFAULT;
my $control_file_on_server	= SVN_REPO_DEFAULT;

my @control_files_in_repo;	#Control File location inside Repository
my $transaction;		#Transaction ID (Used by hook)
my $revision;			#Subversion Revision Number (Used for testing)
my $only_parse;			#Only parse the control file
my $want_help;			#User needs help with options
my $show_perldoc;		#Show the entire Perl documentation
my $svn_user;			#Login User (if required)
my $svn_password;		#Login Password (if required)

my $error_message;		#Error Message to display

GetOptions (
    'svnlook=s'			=> \$svnlook,
    'file=s'			=> \$control_file_on_server,
    'filelocation=s'		=> \@control_files_in_repo,
    't=s'			=> \$transaction,
    'r=i'			=> \$revision,
    'svn_user=s'		=> \$user,
    'svn_password=s'		=> \$password,
    'parse'			=> \$only_parse,
    'help'			=> \$want_help,
    'documentation'		=> \$show_perldoc,
) or $error_message = 'Invalid options';

my $repository = shift;

my $credentials;
if ( defined $svn_user and defined $svn_password ) {
    $credentials = qq(--username="$svn_user" --password="$svn_password");
}
elsif ( defined $svn_user ) {
    $credentials = qq(--username="$svn_user");
}
elsif ( defined $svn_password ) {
    $credentials = qq(--password="$svn_password");
else {
    $credentials = "";
}

if ( not defined $repository ) {
    $error_message .= '\nNeed to pass the repository name';
}

if ( not ( defined $revision or defined $transaction ) ) {
    $error_message .= '\nNeed to specify either a transaction or Subversion revision';
}

if ( defined $revision and defined $transaction ) {
    $error_message .= '\nOnly define either revision or transaction';

if ( not ( defined $control_file or scalar @repo_control_file ) ) {
    $error_message .= '\nNeed to specify a control file';
}

if ( $show_perdoc ) {
    pod2usage ( -exitstatus => 0, -verbose => 2 );
}

if ( $want_help ) {
    pod2usage ( -verbose => 0, -exitstatus => 0 );
}

if ( defined $error_message ) {
    pod2useage ( -message => $error_mssage, -verbose => 2, -exitstatus => 2 );
}

#
########################################################################

########################################################################
# SETUP CONFIGURATION INFORMATION
#

my $configuration = Configuration->new;

$configuration->Repository($svn_repository);
$configuration->Svnlook($svnlook);
$configuration->Credentials($credentials)

my $rev_param = defined $revision ? "-r$revision" : "-t$transaction";
$configuration->Rev_param($rev_param);

my $author;
eval {
    $author = qx( $svnlook author $rev_param  "$svn_repository" );
};
chomp $author;

if ( not $parse_only and not defined $author ) {
    die qq(Author of change cannot be found\n);
}
$configuration->Author($author);

#
# Save Control File on server
#

my @control_file_list;
if ( defined $control_file_on_server ) {
    push @control_file_list, Control_file->new( FILE_ON_SERVER, $control_file_on_server );
}

#
# Save Control Files stored in Repository;
#

for my $control_file ( @control_files_in_repo ) {
    push @control_file_list,
	Control_file->new(FILE_IN_REPO, $control_file, $configuration);
}
#
########################################################################

########################################################################
# BUILD CONTROL FILE SECTIONS
#

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
}
#
########################################################################

########################################################################
# PACKAGE Configuration
#
# Description
# Stores the configuration information for the transaction. This
# includes the initial parameters, the control files, the sections,
# the user, etc.
#    
package Configuration;
use Carp;

sub new {
    my $class		= shift;

    my $self = {};
    bless $self, $class;
    return $self;
}

sub Author {
    my $self		= shift;
    my $author		= shift;

    if ( defined $author ) {
	$self->{AUTHOR} = $author;
    }

    return $self->{AUTHOR};
}

sub Repository {
    my $self		= shift;
    my $repository	= shift;

    if ( defined $repository ) {
	$repository s{\\}{/}g;	#Change from Windows to Unix file separators
	$self->{REPOSITORY} = $repository;
    }

    return $self->{REPOSITORY};
}

sub Rev_param {
    my $self		= shift;
    my $rev_param	= shift;

    if ( defined $rev_param and  $rev_param =~ /^-[tr]/ ) 
	$self->{REV_PARAM} = $revision;
    }
    elsif ( defined $rev_param and $rev_param != /^[tr]/ ) {
	croak qq(Revision parameter must start with "-t" or "-r");
    }
    return $self->{REV_PARAM};
}

sub Svnlook {
    my $self		= shift;
    my $svnlook		= shift;

    if ( defined $svnlook ) {
	$self->{SVNLOOK} = $svnlook;
    }

    return $self->{SVNLOOK};
}

sub Credentials {
    my $self		= shift;
    my $credentials	= shift;

    if ( defined $credentials ) {
	my $self->{CREDENTIALS} = $credentials;
    }
    return $self->{CREDENTIALS};
}

#
########################################################################

########################################################################
# PACKAGE Control_file
#
# Stores Location, Type, and Contents of the Control File
#
package Control_file;
use Carp;

use constant {
    FILE_IN_REPO	=> "R",
    FILE_ON_SERVER	=> "F",
};

sub new {
    my $class		= shift;
    my $type		= shift;
    my $file		= shift;
    my $configuration	= shift;	#Needed if file is in repository

    if ( not defined $type ) {
	croak qq/Must pass in control file type ("R" = in repository. "F" = File on Server")/;
    }
    if ( not defined $file ) {
	croak qq(Must pass in Control File's location);
    }

    if ( not $configuration->isa( "Configuration" ) ) {
	croak qq(Configuration parameter needs to be of a Class "Configuration");
    }
    if ( $type eq FILE_IN_REPO and not defined $configuration ) {
	croak qq(Need to pass a configuration when control file is in the repository);
    }

    my $self = {};
    bless $self, $class;
    $self->Location($type);
    $self->File($file);

    #
    # Get the contents of the file
    #

    if ( $type eq FILE_ON_SERVER ) {
	open my $control_file_fh, "<", $file;
	my @file_contents = < $control_file_fh >;
	close $control_file_fh;
	chomp @file_contents;
	$self->Contents(\@file_contents);
    }
    else {
	my $rev_param   = $configuration->Rev_param;
	my $svnlook     = $configuration->Svnlook;
	my $repository  = $configuration->Repository;
	my $credentials = $configuration->Credentials;
	my @file_contents;
	    eval {
		@file_contents = qx($svnlook cat $credentials $rev_param $repository $file);
	    };
	    if ($@) {
		croak qq(Could not retreive contents of control file "$file" from repository "$repository");
	    }
	    chomp @file_contents;
	    $self->Contents(\@file_contents);
    }

    return $self;
}

sub Location {
    my $self		= shift;
    my $loction		= shift;:

    if ( defined $location ) {
	$self->{LOCATION} = $location;
    }
    return $self->{LOCATION};
}

sub Type {
    my $self		= shift;
    my $type		= shift;

    if ( defined $type ) {
	if ( $type ne FILE_IN_REPO and $type ne FILE_ON_SERVER ) {
	    croak qq(Type must be either ") . FILE_IN_REPO
	    . qq(" or ") . FILE_ON_SERVER . qq(".);
	}
	$self->{TYPE} = $type;
    }
    return $self->{TYPE};
}

sub Contents {
    my $self		= shift;
    my $contents_ref	= shift;

    if ( scalar $contents_ref ) {
	if ( ref $contents_ref ne "ARRAY" ) {
	    croak qq (Contents of control file must be a reference to an array.);
	}
	$self->{CONTENTS} = $contents_ref;
    }

    my @contents = @{ $self->{CONTENTS} };
    return wantarray ? @contents : \@contents;
}
#
########################################################################

########################################################################
# PACKAGE Section
#
# Various Section Objects. Each one is a different type and has
# have different attributes. Master is for general definition
#

package Section;
use Carp;

sub new {
    my $class		= shift;
    my $type		= shift;
    my $description	= shift;
    my $parameter_ref	= shift;

    if ( not defined $type or not defined $description ) {
	croak qq(You must pass in the Section type and Description);
    }

    $type = ucfirst lc $type;	#In the form of a Sub-Class Name

    $class .= "::$type";

    my $self = {};
    bless $self, $class;

    if ( not $self->isa("Section") ) {
	croak qq(Invalid Section type "$type" passed);
    }
    $self->Description($description);
    $self->Parameters($parameter_ref);
    return $self;
}

sub Description {
    my $self		= shift;
    my $description	= shift;

    if ( defined $description ) {
	$self->{DESCRIPTION} = $description;
    }
    return $self->{DESCRIPTION};
}


sub Parameters {
    my $self		= shift;
    my %parameters	= %{ shift() };
    my @req_methods	= @{ shift() };

    #
    # Call the various methods
    #
    my %methods;
    for my $parameter ( keys %parameters ) {
	$method = ucfirst lc $parameter;
	
	$self->$method( $parameters{$parameter} );
    }

    #
    # Make sure all required parameters are here
    #
    for my $method ( @req_methods ) {
	$method = ucfirst lc $method;
	if ( not $self->$method ) {
	    croak qq(Missing required parameter "$method");
	}
    }
}
sub glob2regex {
    my $glob = shift;

    # Due to collision when replacing "*" and "**", we use the NUL
    # character as a temporary replacement for "**" and then replace
    # "*". After this is done, we can replace NUL with ".*".

    $glob =~ s{\\}{/}g; 		#Change backslashes to forward slashes

    # Quote all regex characters
    ( my $regex = $glob ) =~ s{([\.\+\{\}\[\]])}{\\$1}g;

    # Replace double asterisks. Use \0 to mark place
    $regex =~ s{\*\*}{\0}g;

    # Replace single asterisks only
    $regex =~ s/\*/[^\/]*/g;

    # Replace ? with .
    $regex =~ s/\?/./g;

    # Replace \0 with ".*"
    $regex =~ s/\0/.*/g;

    return "^$regex\$";
}
#
# END: CLASS: Section
########################################################################

########################################################################
# CLASS: Section::Group
#
package Section::Group;
use base = qw(Section);
use Carp;

use constant REQUIRED_METHODS	=> qw(Users);

sub Parameters {
    my $self		= shift;
    my $parameter_ref	= shift;

    $self->SUPER::Parameters( $parameter_ref, @{[REQUIRED_METHODS]} );
}

sub Users {
    my $self		= shift;
    my $users		= shift;

    if ( defined $users ) {
	my @users = split /[\s,]+/, $users;
	$self->{USERS} = \@users;
    }

    my @users = @{ $self->{USERS} };
    return wantarray ? @users : \@users;
}
#
# END: CLASS: Section::Group
########################################################################

########################################################################
# CLASS: Section::File
#
package Section::File

use base = qw(Section);
use Carp;

use constant REQUIRED_METHODS 	=> qw(File Users Access);
use constant VALID_CASES	=> qw(match ignore);

sub Parameters {
    my $self		= shift;
    my $parameter_ref	= shift;

    $self->SUPER::Parameters( $parameter_ref, @{[REQUIRED_METHODS]} );
}

sub Match {
    my $self		= shift;
    my $match		= shift;

    if ( defined $match ) {
	$self->{MATCH} = $match;
    }

    return $self->{MATCH};
}

sub Access {
    my $self		= shift;
    my $access		= shift;

    if ( defined $access ) {
	$access = lc $access;
	my %valid_accesses;
	map { $valid_accesses{lc $_} = 1 } +VALID_ACCESSES;
	if ( not exists $valid_accesses{$access} ) {
	    croak qq(Invalid File access "$access");
	}
	$self->{ACCESS} = $access;
    }

    return $self->{ACCESS};
}

sub File {
    my $self		= shift;
    my $file		= shift;

    if ( not exists $file ) {
	croak qq(Matching glob file pattern required);
    }

    my $match = Section::glob2regex( $glob );
    return $self->Match( $match );
}

sub Case {
    my $self		= shift;
    my $case		= shift;

    if ( defined $case ) {
	$case = lc $case;
	my %valid_cases;
	map { $valid_cases{lc $_} = 1 } +VALID_CASES;
	if ( not exists $valid_cases{$case} ) {
	    croak qq(Invalid case "$case" passed to method);
	}
	$self->{CASE} = $case;
    }
    return $self->{CASE};
}

sub Users {
    my $self		= shift;
    my $users		= shift;

    if ( defined $users ) {
	my @users = split /[\s,]+/, $users;
	$self->{USERS} = \@users;
    }

    my @users = @{ $self->{USERS} };
    return wantarray ? @users : \@users;
}
#
# END: CLASS Section::Group
########################################################################

########################################################################
# CLASS: Section::Property
#
package Section::Property;
use Carp;
use base qw(Section);

use constant REQ_PARAMETERS	=> qw(Match, Property, Value, Type);
use constant VALID_TYPES	=> qw(string number regex);
use constant VALID_CASES	=> qw(match ignore);

sub Parameters {
    my $self		= shift;
    my $parameter_ref	= shift;

    $self->SUPER::Parameters( $parameter_ref, @{[REQ_PARAMETERS]} );
}

sub Match {
    my $self		= shift;
    my $match		= shift;

    if ( defined $match ) {
	$self->{MATCH} = $match;
    }
    return $match;
}

sub File {
    my $self		= shift;
    my $glob		= shift;

    if ( not defined $glob ) {
	croak qq(Method is only for setting not fetching);
    }

    my $match = Section::glob2regex($glob);
    return $self->Match( $match );
}

sub Case {
    my $self		= shift;
    my $case		= shift;

    if ( defined $case ) {
	my %valid_cases;
	my $case = lc $case;
	map { $valid_cases{lc $_} = 1 } @{[VALID_CASES]};
	if ( not exists $valid_cases{$case} ) {
	    croak qq(Invalid case "$case");
	}
	$self->{CASE} = $case;
    }
    return $self->{CASE};
}

sub Property {
    my $self		= shift;
    my $property	= shift;

    if ( defined $property ) {
	$self->{PROPERTY} = $property;
    }
    return $self->{PROPERTY};
}

sub Value {
    my $self		= shift;
    my $value		= shift;

    if ( defined $value ) { 
	$self->{VALUE} = $value;
    }
    return $self->{VALUE};
}

sub Type {
    my $self		= shift;
    my $type		= shift;

    if ( defined $type ) {
	my $type = lc $type;
	my %valid_types;
	map { $valid_types{lc $_} = 1 } +VALID_TYPES;
	if ( not exists $valid_types{$type} ) {
	    croak qq(Invalid type of "$type" Property type passed);
	}
    }
}
#
# END: Class: Section::Property
########################################################################

########################################################################
# CLASS: Section::Revprop
#
package Section::Revprop
use Carp;
use base qw(Section);

use constant REQ_PARAMETERS	=> qw(Property, Value, Type);
use constant VALID_TYPES	=> qw(string number regex);

sub Parameters {
    my $self		= shift;
    my $parameter_ref	= shift;

    $self->SUPER::Parameters( $parameter_ref, @{[REQ_PARAMETERS]} );
}

sub Case {
    my $self		= shift;
    my $case		= shift;

    if ( defined $case ) {
	my %valid_cases;
	my $case = lc $case;
	map { $valid_cases{lc $_} = 1 } @{[VALID_CASES]};
	if ( not exists $valid_cases{$case} ) {
	    croak qq(Invalid case "$case");
	}
	$self->{CASE} = $case;
    }
    return $self->{CASE};
}

sub Property {
    my $self		= shift;
    my $property	= shift;

    if ( defined $property ) {
	$self->{PROPERTY} = $property;
    }
    return $self->{PROPERTY};
}

sub Value {
    my $self		= shift;
    my $value		= shift;

    if ( defined $value ) { 
	$self->{VALUE} = $value;
    }
    return $self->{VALUE};
}

sub Type {
    my $self		= shift;
    my $type		= shift;

    if ( defined $type ) {
	my $type = lc $type;
	my %valid_types;
	map { $valid_types{lc $_} = 1 } +VALID_TYPES;
	if ( not exists $valid_types{$type} ) {
	    croak qq(Invalid type of "$type" Property type passed);
	}
    }
}
#
# END: Class: Section::Revprop
########################################################################

########################################################################
# Class: Section::Ban
# 
package Section::Ban;
use base qw(Section);

use Carp;

use constant REQ_PARAMETER	=> qw(Match);
use constant VALID_CASES	=> qw(match ignore);

sub Parameters {
    my $self		= shift;
    my $parameter_ref	= shift;

    $self->SUPER::Parameters( $parameter_ref, \@{[REQ_PARAMETERS]} );
}

sub File {
    my $self		= shift;
    my $glob		= shift;

    my $match = Section::glob2regex( $glob );
    my $self->Match( $match );
}

sub Match {
    my $self		= shift;
    my $match		= shift;

    if ( defined $match ) {
	$self->{MATCH} = $match;
    }
    return $self->{MATCH};
}

sub Case {
    my $self		= shift;
    my $case		= shift;

    if ( defined $case ) {
	$case = lc $case;
	my %valid_cases;
	map { $valid_cases{lc $_} = 1 } +VALID_CASES;
	if ( not exists $valid_cases{$case} ) {
	    croak qq(Invalid case "$case" passed to method);
	}
	$self->{CASE} = $case;
    }
    return $self->{CASE};
}
#
# END: Class Section::Ban
########################################################################

########################################################################
# Class Section::Ldap
#
package Section::Ldap;

BEGIN {
    eval { require Net::LDAP; };
    our ldap_available = 1 if not $@;
}

sub Parameters {

