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

my $error_message;		#Error Message to display

GetOptions (
    'svnlook=s'			=> \$svnlook,
    'file=s'			=> \$control_file_on_server,
    'filelocation=s'		=> \@control_files_in_repo,
    't=s'			=> \$transaction,
    'r=i'			=> \$revision,
    'parse'			=> \$only_parse,
    'help'			=> \$want_help,
    'documentation'		=> \$show_perldoc,
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

if ( not ( defined $control_file or scalar @repo_control_file ) ) {
    $error_message = 'Need to specify a control file';
}

if ( $show_perdoc ) {
    pod2usage ( -exitstatus => 0, -verbose => 2 );
}

if ( $want_help ) {
    pod2usage (
	-message 	=> 'Use "-documentation" to see detailed documentation',
	-verbose	=> 0,
	-exitstatus	=> 0,
    );
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

$configuration->Svnlook($svnlook);
$configuration->Repository($svn_repository);

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

    'filelocation=s'		=> \@control_files_in_repo,
#
# Save Control File on server
#

my $control_file = Control_file->new(FILE_ON_SERVER, $control_file_on_server);
    $configuration->Control_file($control_file);
)

#
# Save Control Files stored in Repository;
#

for my $control_file ( @control_files_in_repo ) {
    my $control_file = Control_file->new(FILE_IN_REPO, $control_file, $configuration);
    $configuration->Control_file($control_file);
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

use constant {
    TRANSACTION		=> "T",
    REVISION		=> "R",
};

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
    my $rev_type	= shift;
    my $revision	= shift;

    if ( defined $rev_type
	    and ( $rev_type ne REVISION or $rev_type ne TRANSACTION ) ) {
	croak qq(Revision Type must be ") . TRANSACTION qq(" or ")
	. REVISION qq(".);
    }

    if ( defined $revision ) {
	$rev_type =  lc $rev_type;
	$self->{REVISION_PARAM} = "-$rev_type" . $revision;
    }

    return $self->{REVISION_PARAM};
}

sub Svnlook {
    my $self		= shift;
    my $svnlook		= shift;

    if ( defined $svnlook ) {
	$self->{SVNLOOK} = $svnlook;
    }

    return $self->{SVNLOOK};
}

sub Control_file {
    my $self 		= shift;
    my $control_file	= shift;

    if ( not defined $self->{CONTROL_FILE_LIST} ) {
	$self->{CONTROL_FILE} = [];
    }

    if ( defined $control_file ) {
	if ( ref $control_file ne "Control_file" ) {
	    croak qq(Control file must be a Control_file object.);
	}

	push @{ $self->{CONTTROL_FILE_LIST} }, $control_file;
    }

    my @control_file_list = @{ $self->{CONTROL_FILE_LIST} };
    return wantarray ? @control_file_list : \@control_file_list;
}

sub Add_section {
    my $self		= shift;
    my $section_obj	= shift;

    if ( not defined $section_obj ) {
	croak qq(Must pass in Section Object);
    }

    my $section_type = ref $section_obj;

    if    ( $section_type eq "Section::Ldap" ) {
	$self->Section_ldap($section_obj);
    }
    elsif ( $section_type eq "Section::Group" )
	$self->Section_group($section_obj);
    }
    elsif ( $section_type eq "Section::File" )
	$self->Section_file($section_obj);
    }
    elsif ( $section_type eq "Section::Ban" )
	$self->Section_ban($section_obj);
    }
    elsif ( $section_type eq "Section::Property" )
	$self->Section_property($section_obj);
    }
    elsif ( $section_type eq "Section::Revprop" )
	$self->Section_revprop($section_obj);
    }
    else {
	croak qq(Invalid type of Section object passed);
    }
    return $self;
}

sub Section_ldap {
    my $self		= shift;
    my $ldap_obj	= shift;

    if ( not defined $self->{SECTION_LDAP} ) {
	$self->{SECTION_LDAP} = [];
    }

    if ( $defined $ldap_obj ) {
	if ( ref $ldap_obj ne "Section::Ldap" ) {
	    croak qq(LDAP info not an Section::Ldap object.);
	}

	push @{ $self->{SECTION_LDAP} }, $ldap_obj;
    }

    my @ldap_list = @{ $self->{SECTION_LDAP} };
    return wantarray ? @ldap_list : \@ldap_list;
}

sub Section_group {
    my $self		= shift;
    my $group_obj	= shift;

    if ( not defined $self->{SECTION_GROUP} ) {
	$self->{SECTION_GROUP} = [];
    }

    if ( $defined $group_obj ) {
	if ( ref $group_obj ne "Section::Group" ) {
	    croak qq(Group info not a Section::Group object.);
	}

	push @{ $self->{SECTION_GROUP} }, $group_obj;
    }

    my @group_list = @{ $self->{SECTION_GROUP} };
    return wantarray ? @group_list : \@group_list;
}

sub Section_file {
    my $self		= shift;
    my $file_obj	= shift;

    if ( not defined $self->{SECTION_FILE} ) {
	$self->{SECTION_FILE} = [];
    }

    if ( $defined $file_obj ) {
	if ( ref $file_obj ne "Section::File" ) {
	    croak qq(File info not a Section::File object.);
	}

	push @{ $self->{SECTION_FILE} }, $file_obj;
    }

    my @file_list = @{ $self->{SECTION_FILE} };
    return wantarray ? @file_list : \@file_list;
}

sub Section_ban {
    my $self		= shift;
    my $ban_obj		= shift;

    if ( not defined $self->{SECTION_BAN} ) {
	$self->{SECTION_BAN} = [];
    }

    if ( $defined $ban_obj ) {
	if ( ref $ban_obj ne "Section::Ban" ) {
	    croak qq(Ban info not a Section::Ban object.);
	}

	push @{ $self->{SECTION_BAN} }, $ban_obj;
    }

    my @ban_list = @{ $self->{SECTION_BAN} };
    return wantarray ? @ban_list : \@ban_list;
}

sub Section_property {
    my $self		= shift;
    my $property_obj	= shift;

    if ( not defined $self->{SECTION_PROPERTY} ) {
	$self->{SECTION_PROPERTY} = [];
    }

    if ( $defined $property_obj ) {
	if ( ref $property_obj ne "Section::Property" ) {
	    croak qq(Property info not a Section::Property object.);
	}

	push @{ $self->{SECTION_PROPERTY} }, $property_obj;
    }

    my @property_list = @{ $self->{SECTION_PROPERTY} };
    return wantarray ? @property_list : \@property_list;
}

sub Section_revprop {
    my $self		= shift;
    my $revprop_obj	= shift;

    if ( not defined $self->{SECTION_REVPROP} ) {
	$self->{SECTION_REVPROP} = [];
    }

    if ( $defined $revprop_obj ) {
	if ( ref $revprop_obj ne "Section::Revprop" ) {
	    croak qq(Revision Property info not a Section::Revprop object.);
	}

	push @{ $self->{SECTION_REVPROP} }, $revprop_obj;
    }

    my @revprop_list = @{ $self->{SECTION_REVPROP} };
    return wantarray ? @revprop_list : \@revprop_list;
}
#
########################################################################

########################################################################
# PACKAGE Control_file
#
# Stores Location, Type, and Contents of the Control File
#
package Control_file;
use Fatal qw(open, close);
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

    my $self = {};
    bless $self, $class;
    $self->Location($type, $file);

    #
    # Get the contents of the file
    #

    if ( defined $type, $file ) {
	if    ( $type eq FILE_ON_SERVER ) {
	    open my $control_file_fh, "<", $file;
	    my @file_contents = < $control_file_fh >;
	    close $control_file_fh;
	    chomp @file_contents;
	    $self->Contents(\@file_contents);
	}
	elsif ( $type eq FILE_IN_REPO ) {
	    if ( if not defined $configuration
		    or ref $configuration ne "Configuration" ) {
		croak qq(Must pass Configuration object when control file is in repo);
	    }
	    my $rev_param  = $configuration->Rev_param;
	    my $svnlook    = $configuration->Svnlook;
	    my $repository = $configuration->Repository;
	    my @file_contents;
	    eval {
		@file_contents = qx($svnlook cat $rev_param $repository $file);
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
    my @params		= @_;

    my ($type, $location);		#Possible Parameters

    if    ( scalar @params == 1 ) {	#Passing only File location
	$location = shift @params;
    }
    elsif ( scalar @params == 2 ) {	#Passing both type and location;
	$type		= shift @params;
	$location	= shift @params;
    }

    if ( defined $type ) {
	$self->Type($type);
    }

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

    if ( not defined $type or not defined $self ) {
	croak qq(You must pass in the Section type and Description);
    }

    $type = ucfirst lc $type;	#In the form of a Sub-Class Name

    $class .= "::$type";
    bless $self, $class;

    if ( not $self->isa("Section") ) {
	croak qq(Invalid Section type "$type" passed);
    }
    $self->Description($description);
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

package Role::Has_users;

sub Users {
    my $self		= shift;
    my $users		= shift;

    if ( defined $users ) {
	my @users = split /(,\s*|\s+)/, $users;
	$self->{USERS} = \@users;
    }
    my @users = @{ $self->{USERS} };
    return wantarray @users : \@users;
}

package Role::Has_file;

use constant VALID_CASE	  => qw(ignore noignore significant);

sub Match {
    my $self		= shift;
    my $match		= shift;

    if ( defined $match ) {
	$self->{MATCH} = $match;
    }

    return $self->{MATCH};
}

sub File {
    my $self		= shift;
    my $file		= shift;

    if ( defined $file ) {
	if ( defined $self->Match ) {
	    croak qq(Cannot define both "match" and "file" parameters for File);
	}
	$self->{FILE} = $file;
	my $match = Section::glob2regex($file);
	$self->Match($match);
    }
    return $self->{FILE};
}

sub Case {
    my $self		= shift;
    my $case		= shift;

    if ( defined $case ) {
	my $case = lc $case;
	my $valid_case_value;

	for my $valid_case ( (VALID_CASE) ) {
	    if ( $valid_case eq $case ) {
		$valid_case_value = TRUE;
		last;
	    }
	}

	if ( not $valid_case_value ) {
	    croak qq(Invalid case "$case" passed);
	}
	$self->{CASE} = $case;
    }

    return $self->{CASE};
}


package Role::Has_prop;

use constant {
    TRUE		=> 1,
    FALSE		=> 0,
};

use constant VALID_TYPE => qw(string number regex);

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
	my $valid_type_value;

	for my $valid_type ( (VALID_TYPE) ) {
	    if ( $valid_type eq $type ) {
		$valid_type_value = TRUE;
		last;
	    }
	}

	if ( not $valid_type_value ) {
	    croak qq(Invalid type "$type" passed);
	}
	$self->{TYPE} = $type;
    }

    return $self->{TYPE};
}

package Section::Ldap;
use base qw(Section);
use Carp;

use Ldap {
    my $self		= shift;
    my @params		= @_;

    my ( $ldap_parameter, $ldap_value );
    if    ( scalar @params == 1 ) {
	$ldap_parameter = "NULL";
	$ldap_value     = shift @params;
    }
    elsif ( scalar @params == 2 ) {
	$ldap_parameter = shift @params;
	$ldap_value     = shift @params;
    }

package Section::Group;
use base qw(Section Role::Has_users);
use Carp;

package Section::File;
use base qw(Section Role::Has_file Role::Has_users);
use Carp;

use constant {
    TRUE		=> 1,
    FALSE		=> 0,
};

use constant VALID_ACCESS => qw(read-only read-write add-only no-add no-delete);

sub Access {
    my $self		= shift;
    my $access		= shift;

    if ( defined $access ) {
	my $access = lc $access;
	my $valid_access_value;

	for my $valid_access ( (VALID_ACCESS) ) {
	    if ( $valid_access eq $access ) {
		$valid_access_value = TRUE;
		last;
	    }
	}

	if ( not $valid_access_value ) {
	    croak qq(Invalid access "$access" passed);
	}
	$self->{ACCESS} = $access;
    }

    return $self->{ACCESS};
}

package Section::Property;
use base qw(Section Role::Has_file Role::Has_prop);
use Carp;

package Section::Revprop;
use base qw(Section Role::Has_prop);
use Carp;

#
########################################################################
