#! /usr/bin/env perl
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
    SVNLOOK_CHANGED	=> 'changed',
    SVNLOOK_PROPLIST	=> 'proplist',
    SVNLOOK_PROPGET	=> 'propget',

    #
    # FILE CHANGE STATUSES
    #
    ADDED		=> 'A',
    DELETED		=> 'D',
    MODIFIED		=> 'U',
};

use constant { 		# Control File Type (package Control)
    FILE_IN_REPO	=> "R",
    FILE_ON_SERVER	=> "F",
};

use constant {		# Revision file Type (package Configuration)
    TRANSACTION 	=> "T",
    REVISION		=> "R",
};

########################################################################
# GET PARAMETERS
#
my %parameters;
$parameters{svnlook}		= SVNLOOK_DEFAULT;
$parameters{file}		= SVN_REPO_DEFAULT;

GetOptions (
    \%parameters,
    'svnlook=s',		# Location of 'svnlook' command
    'file=s',			# Location of control file on server
    'filelocations=s@',		# Location of control files in repository
    't=s',			# Repository Transaction 
    'r=i',			# Repository Revision Number
    'parse',			# Only parse control file for errors
    'help',			# Display command line help
    'documentation',		# Display the entire Documentation
) or pod2usage ( -message => "Invalid parameters passed" );
$parameters{svn_repo} = shift;
my $configuration = Configuration->new;
my @configuration_errors = check_options( $configuration, \%parameters );

if ( @configuration_errors ) {
    print "ERRORS: Bad configuraiton:\n";
    for my $error ( @configuration_errors ) {
	print "* $error\n";
    }
    exit 2;
}
#
#
########################################################################

########################################################################
# MAIN PROGRAM
#

#
# Put all the control files into @control_file_list
#
my @control_file_list;
if ( defined $parameters{file} ) {
    push @control_file_list, Control_file->new( FILE_ON_SERVER, $parameters{file} );
}

for my $control_file ( @{ $parameters{filelocations} } ) {
    push @control_file_list,
	Control_file->new(FILE_IN_REPO, $control_file, $configuration);
}

#
# Parse the control files, and put the information in $sections
#

my $sections = Section_group->new;
my @parse_errors =  parse_control_files( $sections, \@control_file_list );
my @missing_params = verify_parameters( $sections );

#
# If there were any errors in the control files, display them and exit
#
my @errors = ( @parse_errors, @missing_params );
if ( @errors ) {
    for my $error ( @errors ) {
	warn $error->Get_error . "\n";
	warn "-" x 72 . "\n";
    }
    exit 2;
}

#
# Exit if all the user wanted to do was parse the control files
#

if ( exists $parameters{parse} ) {
    print qq(Control files are valid\n);
    print "Resulting structure:\n";
    $Data::Dumper::Indent = 1;
    print Dumper ( $sections ) . "\n";
    exit 0;
}

#
# Find all the groups that the author is in
#

my @authors_groups = find_groups ( $sections );

#
# Purge the file rules, so only rules mentioning users are included
#

my $files_rules_ref = $sections->File;
my $purged_file_rules_ref = purge_file_rules (
    $files_rules_ref,
    $configuration->Author,
    \@authors_groups,
);

#
# Go through all files in the commit and look for file permissions,
# bans, and required properties.
#

my $command = join ( " ",
    $configuration->Svnlook,
    SVNLOOK_CHANGED,
    $configuration->Rev_param,
    $configuration->Repository,
);

open my $cmd_fh, "-|", $command 
    or die qq(Cannot fetch changes "$command");

#
# You also want to parse any control file that was committed to
# make sure it's valid.
#

my %control_files_index;
map { $control_files_index{$_} = 1 } @{ $parameters{filelocations} };
my @violations;
while ( my $line = <$cmd_fh> ) {
    chomp $line;
    $line =~ /\s*(\w)\s+(.*)/;
    my $change_type = $1;
    my $file = "/$2";	# Prepend "/" for root
    push @violations, check_file( $purged_file_rules_ref, $file, $change_type );
    if ( $change_type eq ADDED ) {
	my $ban_rules_ref = $sections->Ban;
	push @violations, check_bans( $ban_rules_ref, $file );
    }
    if ( not $change_type eq DELETED ) {
	my $properties_rules_ref = $sections->Property;
	push @violations, check_properties (
	    $properties_rules_ref,
	    $file,
	    $configuration);
    }
    if ( $control_files_index{$file} ) {  # This is a control file. Parse
	push @violations, check_control_file_for_errors($file, $configuration);
    }
}

#
# Now check for Revision Properties
#

my $prop_rules_ref = $sections->Revprop;
push @violations, check_revision_properties( $prop_rules_ref, $configuration);

#
# If there are violations, report them
#

if ( @violations ) {
    for my $violation ( @violations ) {
	my $file = $violation->File;
	my $error = $violation->Error;
	my $policy = $violation->Policy;
	print STDERR qq(COMMIT VIOLATION:);
	print STDERR qq( In "$file") if $file;
	print STDERR qq(\n);
	print STDERR qq(    $policy\n);
	print STDERR qq(    $error\n);
	print "-" x 72 . "\n";
    }
    exit 2;
}
else {		# There are no violations. Allow commit
    exit 0;
}
#
# END
########################################################################

########################################################################
# SUBROUTINE check_options
#
# Description: Verifies options that were passed into program
#
# Parameters:
#     $configuration:	An object of the $configuration class
#     %parameters:	The parameters in a hash
#
# Returns;
#     @config_errors:	A list of strings describing all configuration
#     			errors. If empty, there are no errors.
#
sub check_options {
    my $configuration	= shift;	# Configuration Object
    my %parameters 	= %{ shift() };

    #
    # Does the user want help?
    #
    if ( exists $parameters{documentation} ) {
	pod2usage ( -exitstatus => 0, -verbose => 2 );
    }

    if ( exists $parameters{help} ) {
	pod2usage ( -verbose => 0, -exitstatus => 0 );
    }

    #
    # Check and set the configurations
    #
    my @config_errors;

    # Location of svnlook command
    eval { $configuration->Svnlook($parameters{svnlook}); };
    if ( $@ ) {
	my $error = qq(Location "$parameters{svnlook}" )
	    . qq(is not a valid "svnlook" command);
	push @config_errors, $error;
    }

    if ( not ( exists $parameters{file}
		or exists $parameters{filelocations} ) ) {
	push @config_errors, "Need to specify a control file";
    }
    
    # Repository Location
    if ( not defined $parameters{svn_repo} ) {
	push @config_errors, "Need to pass the repository name";
    }
    $configuration->Repository($parameters{svn_repo});

    # Transaction or Revision Number
    if ( not ( exists $parameters{r} or exists $parameters{t} ) ) {
	push @config_errors, "Must specify a repo transaction or revision";
    }

    if ( exists $parameters{r} and exists $parameters{t} ) {
	push @config_errors, qq(Cannot specify both "-t" and "-r" parameters");
    }

    if ( exists $parameters{r} ) {
	$configuration->Rev_param( "-r $parameters{r}" );
    }
    elsif ( exists $parameters{t} ) {
	$configuration->Rev_param( "-t $parameters{t}" );
    }

    eval { $configuration->Set_author if not $parameters{parse}; };
    if ( $@ ) {
	push @config_errors, qq(Cannot set author: $@);
    }
    return wantarray ? @config_errors : \@config_errors;
}
#
########################################################################

########################################################################
# SUBROUTINE parse_control_files
#
# Description: Parses the various control files in the configuration
#              and puts them into a handy-dandy convient structre for
#              future processing.
#
# Parameters:
#     $sections:		An object of Section_group type. This
#     				structure will be modified with the contents
#     				of all the various control files.
#     $control_file_list_ref	A list of all the Control_file class objects,
#     				each representing a control file that is to
#     				be parsed.
# Returns:
#     @parse_errors:		A list of all the errors found when parsing
#				the various control files. These are objects
#				of the Parse_error class.
# 
sub parse_control_files {
    my $sections		= shift;
    my $control_file_list_ref	= shift;

    my @parse_errors;		# All errors found

    for my $control_file ( @{ $control_file_list_ref } ) {
	my $section;		# Section object: defined when section header is read
	my $section_error;	# Does the section header have an error?
	my $line_number = 0;	# Track line numbers in control files for errors
	for my $line ( $control_file->Content ) {
	    $line_number++;
	    next unless $line;	# Ignore blank lines
	    if ( $line =~ SECTION_HEADER ) {
		my $section_type = $1;
		my $description  = $2;
		eval { $section = Section->new( $section_type, $description ); };
		if ( $@ ) {
		    $section_error = 1;	# Bad Section header, skip to next section
		    my $error = qq(Invalid Section Type "$section_type");
		    push @parse_errors,
			Parse_error->new($error, $control_file, $line_number);
		}
		else {
		    $section_error = 0;	# Section Header is good
		    $sections->Add($section);
		    $section->Control_file_line($line_number);
		    $section->Control_file($control_file);
		}
	    }
	    elsif ( $line =~ PARAMETER_LINE ) {
		my $parameter	= $1;
		my $value	= $2;
		if ( not $section_error ) {
		    eval { $section->Parameter( $parameter, $value ); };
		    if ($@) {
			my $error = qq(Invalid Parameter "$parameter");
			push @parse_errors,
			    Parse_error->new($error, $control_file, $line_number);
		    }
		}
	    }
	    else {	# Invalid Line
		my $error = qq(Invalid Line in "$line");
		push @parse_errors,
	    	    Parse_error->new($error, $control_file, $line_number);
	    }
	}
    }
    return wantarray ? @parse_errors : \@parse_errors
}


#
########################################################################

########################################################################
# SUBROUTINE verify_parameters
#
sub verify_parameters {
    my $sections	= shift;

    my @missing_params;
    for my $method ( $sections->Sections ) {
	for my $section ( $sections->$method ) {
	    eval { $section->Verify_parameters; };
	    if ($@) {
		my $control_file = $section->Control_file;
		my $line_number = $section->Control_file_line;
		( my $error = $@ ) =~ s/ at .*$//;
		push @parse_errors,
		    Parse_error->new( $error, $control_file, $line_number);
	    }
	}
    }
    return @missing_params;
}
#
########################################################################

########################################################################
# SUBROUTINE find_groups
#
# Description: This subroutine locates all of the groups that the
#              Author is a member of. It used Ldap and Section group
#              definitions. If a group definition contains a group, and
#              one of the members of that group is a group the author is
#              in, the author will be a member of the parent group.
#
# Parameters:
#    $section:		A Section_group object representing all of the
#    			various control file configurations. The
#    			$section->Group and $section->Ldap groups will both
#    			be parsed.
#
# Returns:
#   @author_groups:	A list of groups that the Author of the change
#   			belongs to.
#
sub find_groups {
    my $section		= shift;

    if ( ref $section ne "Section_group" ) {
	die qq(Must pass object of Section_group class);
    }

    my @authors_groups = qw(all);	# Everyone is a member of "ALL"
    my %authors_group_index;
    #
    # LDAP Groups User Is In
    #
    for my $ldap ( $sections->Ldap ) {
	push @authors_groups, $ldap->Ldap_groups($configuration->Ldap_user);
    }
    map { $authors_group_index{$_} = 1 } @authors_groups;
    #
    # Get Group List Defined in Control File
    #

    GROUP:
    for my $group ( $sections->Group ) {
	my $group_name = lc $group->Description;
	for my $user ( $group->Users ) {
	    if ( $user eq $configuration->Author ) {	# Author is in this group
		push @authors_groups, $group_name;
		$authors_group_index{$group_name} = 1;
		next GROUP;
	    }
	    if ( $user =~ s/^\@(.+)/$1/ ) {		# This is a group and not a user
		#
		# See if Author is a member of this group
		#
		my $group = $1;
		if ( $authors_group_index{$group} ) {
		    push @authors_groups, $group_name;
		    $authors_group_index{$group_name} = 1;
		    next GROUP;
		}
	    }
	}
    }
    return wantarray ? @authors_groups : \@authors_groups;
}
#
########################################################################

########################################################################
# SUBROUTINE purge_file_rules
#
# Description:	This purges all unnecessary rules from a list of
# 		Section::File types. Unnecessary rules are rules
# 		that don't involve the author (i.e., the author nor
# 		one of the groups the author is in is in File->Users).
#
#               This also will substitute the <USER> string for the author's
#               name.
# Parameter:
#    @file_rules:	A list of Section::File object types.
#    $author:		The author.
#    @author_groups:	A list of all groups the author is already a member
#    			of.
# Returns:
#    @purged_rules: 	A list of the purged rules.
#
sub purge_file_rules {
    my $file_rules_ref	= shift;
    my $author		= shift;
    my $groups_ref	= shift;

    my @authors_groups = @{ $groups_ref };
    my %authors_groups_index;
    map { $authors_groups_index{$_} = 1 } @authors_groups;

    my @purged_file_rules;
    for my $file_rule ( @{ $file_rules_ref } ) {
	my $regex = $file_rule->Match;
	#
	# Substitute <USER> with author's name
	#
	if ( $regex =~ s/<USER>/$author/g ) {
	    $file_rule->Match($regex);
	}
	for my $user ( $file_rule->Users ) {
	    if ( $user =~ /^\@(.*)/ ) { 	# This is a group
		my $group = $1;
		if ( $authors_groups_index{$group} ) {
		    push @purged_file_rules, $file_rule;
		}
	    }
	    else {				# This is a user. Is this the author?
		if ( $author eq $user ) {
		    push @purged_file_rules, $file_rule;
		}
	    }
	} 	# for my $user ( $file_rule->Users )
    }	# for my $file_rule ( @{ $file_rules_ref } )
    return wantarray ? @purged_file_rules: \@purged_file_rules;
}
#
########################################################################

sub check_file { 
    my $file_rules_ref	= shift;
    my $file_name	= shift;
    my $change_type	= shift;

    my %change_desc = (
	A  => "add",
	D  => "delete",
	U  => "modify",
	UU => "modify",
	_U => "modify property",
    );

    my @violations;
    my $description;		# Need last not permitted description
    my $permitted = 1;		# Assume user has permission to do this
    for my $file_rule ( @{ $file_rules_ref } ) {
	my $regex = $file_rule->Match;
	my $access = $file_rule->Access;
	my $case = $file_rule->Case;

	if ( $case eq "ignore" ? $file_name =~ /$regex/i : $file_name =~ /$regex/ ) {
	    if    ( $access eq "read-write" ) {
		$permitted = 1;
	    }
	    elsif ( $access eq "read-only" ) {
		$permitted = 0;
		$description = $file_rule->Description;
	    }
	    elsif ( $access eq "add-only" ) {
		$permitted =  $change_type eq ADDED ? 1 : 0;
		$description = $file_rule->Description if not $permitted;
	    }
	    elsif ( $access eq "no-add" ) {
		$permitted = $change_type ne ADDED ? 1 : 0;
		$description = $file_rule->Description if not $permitted;
	    }
	    elsif ( $access eq "no-delete" ) {
		$permitted = $change_type ne DELETED ? 1 : 0;
		$description = $file_rule->Description if not $permitted;
	    }
	}
    }
    if ( not $permitted ) {
	my $violation = Violation->new( $file_name, $description );
	$violation->Policy( qq(You don't have access to $change_desc{$change_type} $file_name.) );
	return $violation;
    }
    else {
	return;
    }
}

sub check_bans {
    my $ban_rules_ref	= shift;
    my $file_name	= shift;

    for my $ban_rule ( @{ $ban_rules_ref } ) {
	my $regex = $ban_rule->Match;
	my $case = $ban_rule->Case;
	if ( $case eq "ignore" ? $file_name =~ /$regex/i : $file_name =~ /$regex/ ) {
	    my $violation = Violation->new( $file_name, $ban_rule->Desciption );
	    $violation->Policy("File name is not permitted to be added into repository");
	    return $violation;
	}
    }
    return;	# Not banned
}

sub check_properties {
    my $prop_rules_ref	= shift;
    my $file		= shift;
    my $configuration	= shift;

    my @violations;
    my %properties;	# Properties on the file

    #
    # Fetch all current properties and their values for this file
    #
    my $command = join ( " ",	# Find what properties the file has
	$configuration->Svnlook,
	SVNLOOK_PROPLIST,
	$configuration->Rev_param,
	$configuration->Repository,
	$file,
    );

    my @properties = qx($command);
    chomp @properties;
    while ( my $property = <@properties> ) {	# Fetch the property for that file
	next if $property eq "";
	my $command = join ( " ",
	    $configuration->Svnlook,
	    SVNLOOK_PROPGET,
	    $configuration->Rev_param,
	    $configuration->Repository,
	    $property,
	    $file,
	);
	chomp ( $properties{$property} = qx($command) );
    }

    #
    # We now have a list of properties and their values. Let's see which ones we need
    #
    PROP_RULE:
    for my $prop_rule ( @{ $prop_rules_ref } ) {
	my $regex = $prop_rule->Match;
	if ( ( $prop_rule->Case eq "ignore" and $file !~ /$regex/i )
		or ( not $prop_rule->Case eq "ignore" and $file !~ /$regex/ ) ) {
	    next PROP_RULE;	# This rule doesn't apply to the file
	}
	
	#
	# Matching Prop_rule found: See if the file has that property
	#
	my $property = $prop_rule->Property;
	if ( not exists $properties{$property} ) {	# Missing property
	    my $violation = Violation->new( $file, $prop_rule->Description );
	    $violation->Policy( qq(Missing property "$property" on "$file") );
	    push @violations, $violation;
	    next PROP_RULE;
	}

	#
	# File has that property: See if the value matches what it should be
	#
	else {	# Property exists: See if it matches
	    my $prop_value = $prop_rule->Value;
	    if    ( $prop_rule->Type eq "string"
		    and $properties{$property} ne $prop_value ) {
		my $violation = Violation->new( $file, $prop_rule->Description );
		$violation->Politcy( qq(Property "$property" did not match value "$prop_value") );
		push @violations, $violation;
		next PROP_RULE;

	    }
	    elsif ( $prop_rule->Type eq "number"
		    and $properties{$property} != $prop_value ) {
		my $violation = Violation->new( $file, $prop_rule->Description );
		$violation->Politcy( qq(Property "$property" did not equal "$prop_value") );
		push @violations, $violation;
		next PROP_RULE;
	    }
	    elsif ( $prop_rule->Type eq "regex" 
		    and $properties{$property} !~ /$prop_value/ ) {
		my $violation = Violation->new( $file, $prop_rule->Description );
		$violation->Politcy( qq(Property "$property" did not match regex "$prop_value") );
		push @violations, $violation;
		next PROP_RULE;
	    }
	}	# NEXT PROP_RULE

    } 
    return @violations;
}

sub check_revision_properties {
    my $prop_rules_ref	= shift;
    my $configuration	= shift;

    my @violations;
    my %properties;	# Properties on the file

    #
    # Fetch all current properties and their values for this file
    #
    my $command = join ( " ",	# Find what properties the file has
	$configuration->Svnlook,
	SVNLOOK_PROPLIST,
	"--revprop",
	$configuration->Rev_param,
	$configuration->Repository,
    );

    my @revprops = qx($command);
    chomp @revprops;
    for my $property ( @revprops ) {
	$property =~ s/^\s*//;
	my $command = join ( " ",
	    $configuration->Svnlook,
	    SVNLOOK_PROPGET,
	    "--revprop",
	    $configuration->Rev_param,
	    $configuration->Repository,
	    $property,
	);
	chomp ( $properties{$property} = qx($command) );
    }

    #
    # We now have a list of properties and their values. Let's see which ones we need
    #
    PROP_RULE:
    for my $prop_rule ( @{ $prop_rules_ref } ) {
	my $property = $prop_rule->Property;
	if ( not exists $properties{$property} ) {	# Missing property
	    my $violation = Violation->new( "", $prop_rule->Description );
	    $violation->Policy( qq(Missing revision property "$property" on commit) );
	    push @violations, $violation;
	    next PROP_RULE;
	}

	#
	# File has that property: See if the value matches what it should be
	#
	else {	# Property exists: See if it matches
	    my $prop_value = $prop_rule->Value;
	    if    ( $prop_rule->Type eq "string"
		    and $properties{$property} ne $prop_value ) {
		my $violation = Violation->new( "", $prop_rule->Description );
		$violation->Policy( qq(Revision Property "$property" did not match value "$prop_value") );
		push @violations, $violation;
		next PROP_RULE;

	    }
	    elsif ( $prop_rule->Type eq "number"
		    and $properties{$property} != $prop_value ) {
		my $violation = Violation->new( "", $prop_rule->Description );
		$violation->Policy( qq(Revision property "$property" did not equal "$prop_value") );
		push @violations, $violation;
		next PROP_RULE;
	    }
	    elsif ( $prop_rule->Type eq "regex" 
		    and $properties{$property} !~ /$prop_value/ ) {
		my $violation = Violation->new( "", $prop_rule->Description );
		$violation->Policy( qq(Revision property "$property" did not match regex "$prop_value") );
		push @violations, $violation;
		next PROP_RULE;
	    }
	}	# NEXT PROP_RULE

    } 
    return @violations;
}

sub check_control_file {
    my $file		= shift;
    my $configuration	= shift;

    my @control_file = ( Control_file->new(FILE_IN_REPO, $file, $configuration) );
    my $sections = Section_group->new;
    my @parse_errors =  parse_control_files( $sections, \@control_file_list );

    my $error_message;
    if ( @parse_errors ) {
	for my $error ( @parse_errors ) {
	    $error_message .= $error->Get_error . "\n";
	    $error_message .= "-" x 72 . "\n";
	}
	my $violation = Violation->new( $file, "$error_message" );
	$violation->Policy("Invalid Control File");
	my @violations = ( $violation );
	return wantarray ? @violations : \@violations;

    }
    else {
	return;
    }
}


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
	$self->Ldap_user($author);	# Preserved with spaces and case;
	$author =~ s/\s+/_/g;		# Replace whitespace with underscores
	$self->{AUTHOR} = lc $author;
    }
    return $self->{AUTHOR};
}

sub Ldap_user {
    my $self		= shift;
    my $ldap_user	= shift;

    if ( defined $ldap_user ) {
	$self->{LDAP_USER} = $ldap_user;
    }
    return $self->{LDAP_USER};
}

sub Set_author {
    my $self		= shift;

    if ( not $self->Svnlook ) {
	croak qq(Need to set where "svnlook" command is located first);
    }

    if ( not $self->Rev_param ) {
	croak qq(Need to set the revision or transaction parameter first);
    }
    if ( not $self->Repository ) {
	croak qq(Need to set the repository location first);
    }

    my $svnlook = $self->Svnlook;
    my $rev	= $self->Rev_param;
    my $repo	= $self->Repository;
    my $author;
    my $command = qq("$svnlook" author $rev "$repo");
    eval { $author = qx($command) };
    if ( $@ ) {
	croak qq(Failed to execute command "$command");
    }
    chomp $author;
    if ( not $author ) {
	croak qq(Cannot locate author of revision "$rev" in repo "$repo");
    }
    return $self->Author($author);
}

sub Repository {
    my $self		= shift;
    my $repository	= shift;

    if ( defined $repository ) {
	$repository =~ s{\\}{/}g;	# Change from Windows to Unix file separators
	$self->{REPOSITORY} = $repository;
    }

    return $self->{REPOSITORY};
}

sub Rev_param {
    my $self		= shift;
    my $rev_param	= shift;

    if ( defined $rev_param and  $rev_param =~ /^-[tr]/ )  {
	$self->{REV_PARAM} = $rev_param;
    }
    elsif ( defined $rev_param and $rev_param !~ /^[tr]/ ) {
	croak qq(Revision parameter must start with "-t" or "-r");
    }
    return $self->{REV_PARAM};
}

sub Svnlook {
    my $self		= shift;
    my $svnlook		= shift;

    if ( defined $svnlook ) {
	if ( not -x $svnlook ) {
	    croak qq(The program "$svnlook" is not an executable program");
	}
	$self->{SVNLOOK} = $svnlook;
    }

    return $self->{SVNLOOK};
}
#
# END: Class:Configuration
########################################################################

########################################################################
# PACKAGE Control_file
#
# Stores Location, Type, and Contents of the Control File
#
package Control_file;
use Data::Dumper;
use Carp;

use constant {
    FILE_IN_REPO	=> "R",
    FILE_ON_SERVER	=> "F",
};

sub new {
    my $class		= shift;
    my $type		= shift;
    my $location	= shift;
    my $configuration	= shift;	# Needed if file is in repository

    if ( not defined $type ) {
	croak qq/Must pass in control file type ("R" = in repository. "F" = File on Server")/;
    }
    if ( not defined $location ) {
	croak qq(Must pass in Control File's location);
    }

    if ( $type eq FILE_IN_REPO and not defined $configuration ) {
	croak qq(Need to pass a configuration when control file is in the repository);
	if ( not $configuration->isa( "Configuration" ) ) {
	    croak qq(Configuration parameter needs to be of a Class "Configuration");
	}
    }

    my $self = {};
    bless $self, $class;
    $self->Type($type);
    $self->Location($location);

    #
    # Get the contents of the file
    #

    if ( $type eq FILE_ON_SERVER ) {
	my $control_file_fh;
	open $control_file_fh, "<", $location or
	    croak qq(Invalid Control file "$location" on server.);
	my @file_contents = <$control_file_fh>;
	close $control_file_fh;
	chomp @file_contents;
	$self->Content(\@file_contents);
    }
    else {
	my $rev_param   = $configuration->Rev_param;
	my $svnlook     = $configuration->Svnlook;
	my $repository  = $configuration->Repository;
	my @file_contents;
	eval {
	    @file_contents = qx($svnlook cat $rev_param $repository $location);
	};
	if ($@) {
	    croak qq(Couldn't retreive contents of control file)
	    . qq("$location" from repository "$repository");
	}
	$self->Content(\@file_contents);
    }
    return $self;
}

sub Location {
    my $self		= shift;
    my $location	= shift;

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

sub Content {
    my $self		= shift;
    my $contents_ref	= shift;

    $self->{CONTENTS} = [] if not exists $self->{CONTENTS};
    if ( defined $contents_ref ) {
	my @contents;
	for my $line ( @{$contents_ref} ) {
	    $line =~ s/^\s*$//;		# Make blank lines empty
	    $line =~ s/^\s*[#;].*//;	# Make comment lines empty
	    push @contents, $line;
	}
	$self->{CONTENTS} = \@contents;
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
use Data::Dumper;
use Carp;

use constant {
    FILE_IN_REPO	=> "R",
    FILE_ON_SERVER	=> "F",
};

sub new {
    my $class		= shift;
    my $type		= shift;
    my $description	= shift;

    if ( not defined $type or not defined $description ) {
	croak qq(You must pass in the Section type and Description);
    }

    $type = ucfirst lc $type;	# In the form of a Sub-Class Name

    $class .= "::$type";

    my $self = {};
    bless $self, $class;

    if ( not $self->isa("Section") ) {
	croak qq(Invalid Section type "$type" in control file);
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

sub Control_file {
    my $self		= shift;
    my $control_file 	= shift;

    if ( defined $control_file ) {
	if ( ref $control_file ne "Control_file" ) {
	    croak qq(Control file must be of a type "Control_file");
	}
	$self->{CONTROL_FILE_NAME} = $control_file;
    }
    return $self->{CONTROL_FILE_NAME};
}

sub Control_file_line {
    my $self		= shift;
    my $line_number	= shift;

    if ( defined $line_number ) {
	$self->{LINE_NUMBER} = $line_number;
    }
    return $self->{LINE_NUMBER};
}

sub Parameter {
    my $self		= shift;
    my $parameter	= shift;
    my $value		= shift;

    if ( not defined $parameter ) {
	croak qq(Missing parameter "parameter");
    }
    my $method = ucfirst lc $parameter;

    if ( not $self->can($method) ) {
	croak qq(Invalid parameter "$parameter" passed);
    }

    if ( defined $value ) {
	return $self->$method($value);
    }
    else {
	return $self->$method;
    }
}

sub Verify_parameters {
    my $self		= shift;
    my $req_method_ref	= shift;

    my @req_methods = @{ $req_method_ref };

    #
    # Call the various methods
    #
    for my $method ( @req_methods ) {
	$method = ucfirst lc $method;
	eval { $self->$method; };
	if ( $@ or not $self->$method ) {
	    croak qq(Missing required parameter "$method");
	}
    }
    return 1;
}

sub glob2regex {
    my $glob = shift;

    # Due to collision when replacing "*" and "**", we use the NUL
    # character as a temporary replacement for "**" and then replace
    # "*". After this is done, we can replace NUL with ".*".

    $glob =~ s{\\}{/}g; 		# Change backslashes to forward slashes

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
use Data::Dumper;
use base qw(Section);
use Carp;

use constant REQ_PARAMETERS	=> qw(Users);

sub Users {
    my $self		= shift;
    my $users		= shift;

    if ( defined $users ) {
	$self->{USERS} = [];	# Redefines all users: Don't add new ones
	for my $user ( split /[\s,]+/, $users ) {
	    push @{ $self->{USERS} }, lc $user;
	}
    }
    my @users = @{ $self->{USERS} };
    return wantarray ? @users : \@users;
}

sub Verify_parameters {
    my $self =		shift;

    my @required_parameters = REQ_PARAMETERS;
    return $self->SUPER::Verify_parameters( \@required_parameters );
}
#
# END: CLASS: Section::Group
########################################################################

########################################################################
# CLASS: Section::File
#
package Section::File;
use base qw(Section);
use Carp;

use constant REQ_PARAMETERS 	=> qw(Match Users Access);
use constant VALID_CASES	=> qw(match ignore);
use constant VALID_ACCESSES	=> qw(read-only read-write add-only no-delete no-add);

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
    my $glob		= shift;

    if ( not defined $glob ) {
	croak qq(Matching glob file pattern required);
    }

    my $match = Section::glob2regex( $glob );
    return $self->Match( $match );
}

sub Case {
    my $self		= shift;
    my $case		= shift;

    $self->{CASE} = "match" if not exists $self->{CASE};	# Default
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
	my @users = map { lc } split /[\s,]+/, $users;	# Lower case!
	$self->{USERS} = \@users;
    }

    my @users = @{ $self->{USERS} };
    return wantarray ? @users : \@users;
}

sub Verify_parameters {
    my $self =		shift;

    my @required_parameters =	REQ_PARAMETERS;
    return $self->SUPER::Verify_parameters( \@required_parameters );
}
#
# END: CLASS Section::File
########################################################################

########################################################################
# CLASS: Section::Property
#
package Section::Property;
use Carp;
use base qw(Section);

use constant REQ_PARAMETERS	=> qw(Match Property Value Type);
use constant VALID_TYPES	=> qw(string number regex);
use constant VALID_CASES	=> qw(match ignore);

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

    $self->{CASE} = "match" if not exists $self->{CASE};	# Default;
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
	$self->{TYPE} = $type;
    }
    return $self->{TYPE};
}

sub Verify_parameters {
    my $self =		shift;

    my @required_parameters = REQ_PARAMETERS;
    return $self->SUPER::Verify_parameters( \@required_parameters );
}
#
# END: Class: Section::Property
########################################################################

########################################################################
# CLASS: Section::Revprop
#
package Section::Revprop;
use Carp;
use base qw(Section);

use constant REQ_PARAMETERS	=> qw(Property Value Type);
use constant VALID_TYPES	=> qw(string number regex);

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
	$self->{TYPE} = $type;
    }
    return $self->{TYPE};
}

sub Verify_parameters {
    my $self =		shift;

    my @required_parameters = REQ_PARAMETERS;
    return $self->SUPER::Verify_parameters( \@required_parameters );
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

use constant REQ_PARAMETERS	=> qw(Match);
use constant VALID_CASES	=> qw(match ignore);

sub File {
    my $self		= shift;
    my $glob		= shift;

    my $match = Section::glob2regex( $glob );
    $self->Match( $match );
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

    $self->{CASE} = "match" if not exists $self->{CASE};	# Default;
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

sub Verify_parameters {
    my $self =		shift;

    my @required_parameters = REQ_PARAMETERS;
    return $self->SUPER::Verify_parameters( \@required_parameters );
}
#
# END: Class Section::Ban
########################################################################

########################################################################
# Class Section::Ldap
#
package Section::Ldap;
use Data::Dumper;
use Carp;
use base qw(Section);

use constant REQ_PARAMETERS	=> qw(ldap base);

use constant {
    DEFAULT_NAME_ATTR	=> "sAMAccountName",
    DEFAULT_GROUP_ATTR	=> "memberOf",
    DEFAULT_TIMEOUT	=> 5,
};

BEGIN {
    eval { require Net::LDAP; };
    our $ldap_available = 1 if not $@;
}
our $ldap_available;

sub Description {
    my $self		= shift;
    my $description	= shift;

    if ( not $ldap_available ) {
	carp qq(ERROR: Need to install Perl module Net::LDAP\n)
	. qq(       to be able to use LDAP groups);
	croak qq(Need to install Perl module Net::LDAP);
    }
    return $self->SUPER::Description( $description );
}


sub Ldap {
    my $self		= shift;

    if ( not $self->Description ) {
	croak qq(Missing description which contains the LDAP server list);
    }

    my @ldaps = split /[\s,]+/, $self->Description;	
    return wantarray ? @ldaps : \@ldaps;
}

sub Username_attr {
    my $self		= shift;
    my $username_attr	= shift;

    if ( defined $username_attr ) {
	$self->{USER_NAME_ATTR} = $username_attr;
    }

    if ( not exists $self->{USER_NAME_ATTR} ) {
	$self->{USER_NAME_ATTR} = DEFAULT_NAME_ATTR;
    }
    return $self->{USER_NAME_ATTR};
}

sub Group_attr {
    my $self		= shift;
    my $group_attr	= shift;

    if ( defined $group_attr ) {
	$self->{GROUP_ATTR} = $group_attr;
    }
    if ( not exists $self->{GROUP_ATTR} ) {
	$self->{GROUP_ATTR} = DEFAULT_GROUP_ATTR;
    }
    return $self->{GROUP_ATTR};
}

sub Base {
    my $self		= shift;
    my $base		= shift;

    if ( defined $base) {
	$self->{BASE} = $base;
    }
    return $self->{BASE};
}

sub User_dn {
    my $self		= shift;
    my $user_dn		= shift;

    if ( defined $user_dn ) {
	$self->{USER_DN} = $user_dn;
    }
    return $self->{USER_DN};
}

sub Password {
    my $self		= shift;
    my $password	= shift;

    if ( defined $password ) {
	$self->{PASSWORD} = $password;
    }
    return $self->{PASSWORD};
}

sub Search_base {
    my $self		= shift;
    my $search_base	= shift;

    if ( defined $search_base ) {
	$self->{SEARCH_BASE} = $search_base;
    }
    return $self->{SEARCH_BASE};
}

sub Timeout {
    my $self		= shift;
    my $timeout		= shift;

    if ( defined $timeout ) {
	if ( $timeout =~ /^\d+$/ ) {
	    croak qq(Timeout value for ldap server must be an integer);
	}
	$self->{TIMEOUT} = $timeout;
    }

    if ( not exists $self->{TIMEOUT} ) {
	$self->{TIMEOUT} = DEFAULT_TIMEOUT;
    }
    return $self->{TIMEOUT};
}

sub Ldap_groups {
    my $self		= shift;
    my $user		= shift;

    my $ldap_servers	= $self->Ldap;
    my $user_dn		= $self->User_dn;
    my $password	= $self->Password;
    my $timeout		= $self->Timeout;

    my $username_attr	= $self->Username_attr;
    my $group_attr	= $self->Group_attr;

    if ( not defined $user ) {
	croak qq(Need to pass in a user name);
    }

    #
    # Create LDAP Object
    #
    my $ldap = Net::LDAP->new( $ldap_servers,
	timeout => $timeout,
	onerror => "die"
    );
    if ( not defined $ldap ) {
	croak qq(Could not connect to LDAP servers:)
	. join( ", ", @{ $ldap_servers } ) . qq( Timeout = $timeout );
    }
    #
    # Try a bind
    #
    my $message;
    eval {
	if ( $user_dn and $password ) {
	    $message = $ldap->bind( $user_dn, password => $password );
	}
	elsif ( $user_dn and not $password ) {
	    $message = $ldap->bind( $user_dn );
	}
	else {
	    $message = $ldap->bind;
	}
    };
    if ( $@ ) {
	no warnings qw(uninitialized);
	croak qq(Could not "bind" to LDAP server.) 
	. qq( User DN: "$user_dn" Password: "$password");
	use warnings qw(uninitialized);
    }

    #
    # Search
    #

    my $search_base	= $self->Search_base;
    my $base_dn		= $self->Base;
    my $search;
    if ( not $base_dn ) {
	croak qq(Missing Base DN definition. Cannot do LDAP Search for groups);
    }
    eval {
	if ( $search_base ) {
	    $search = $ldap->search(
		base => $base_dn,
		basename => $search_base,
		filter => "($username_attr=$user)",
	    );
	}
	else {
	    $search = $ldap->search(
		base => $base_dn,
		filter => "($username_attr=$user)"
	    );
	}
    };
    if ( $@ ) {
	croak qq(Search of LDAP tree failed ($username_attr=$user));
    }

    #
    # Get the Entry
    #
    my $entry = $search->pop_entry;		# Should only return a single entry

    #
    # Get the attribute of that entry
    #

    my @groups;
    for my $group ( $entry->get_value( $group_attr ) ) {
	$group =~ s/cn=(.+?),.*/\L$1\U/i;  	# Just the "CN" value
	$group = lc $group;			# Make all lowercase
	$group =~ s/\s+/_/g;			# normalize white spaces
	push @groups, $group;
    }
    return wantarray ? @groups : \@groups;
}

sub Verify_parameters {
    my $self =		shift;

    my @required_parameters = REQ_PARAMETERS;
    return $self->SUPER::Verify_parameters( \@required_parameters );
}
#
# END: Class: Section::Ldap
########################################################################

########################################################################
# Class Parse_error;
#
package Parse_error;
use Carp;

sub new {
    my $class		= shift;
    my $description	= shift;
    my $control_file	= shift;
    my $line_number	= shift;

    my $self = {};
    bless $self, $class;

    $self->Description($description);
    $self->Control_file($control_file);
    $self->Line_number($line_number);
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

sub Control_file {
    my $self		= shift;
    my $control_file	= shift;

    if ( defined $control_file ) {
	if ( not ref $control_file eq "Control_file" ) {
	    croak qq( Control file parameter must be a Control_file object);
	}
	$self->{CONTROL_FILE} = $control_file;
    }
    return $self->{CONTROL_FILE};
}

sub Line_number {
    my $self		= shift;
    my $line_number	= shift;

    if ( defined $line_number ) {
	if ( $line_number !~ /^\d+$/ ) {
	    croak qq(Line number must be an integer);
	}
	$self->{LINE_NUMBER} = $line_number - 1;
    }
    return $self->{LINE_NUMBER};
}

sub Get_error { 
    my $self		= shift;

    my $control_file	= $self->Control_file;
    my $file_name 	= $control_file->Location;
    my $location	= $control_file->Type;
    my @file_contents	= $control_file->Content;

    #
    # You need to push the line that has the error
    # and the entire section which may mean lines
    # before and after the error
    #

    my $line_number = $self->Line_number;
    my $line = $file_contents[$line_number];
    my @section_lines;
    push @section_lines, "-> $line";
    #
    # Unshift lines before the error until at beginning
    # of the control file, or at a section heading
    #
    while ( $line_number != 0
	    and $file_contents[$line_number] !~ /^\s*\[/ ) {
	$line_number--;
	my $line = $file_contents[$line_number];
	unshift @section_lines, "   $line";
    }
    #
    # Push lines after error until next section
    # hearder or the end of file
    #
    $line_number = $self->Line_number + 1;
    while ( $line_number <= $#file_contents
	    and $file_contents[$line_number] !~ /^\s*\[/ ) {
	my $line = $file_contents[$line_number];
	$line_number++;
	next if not $line;
	push @section_lines, "   $line";

    }
    #
    # Now generate the error message
    #

    my $description =  "ERROR: In parsing Control File";
    $description .= qq( "$file_name" ($location));
    $description .= " Line# " . $self->Line_number . "\n";
    $description .= "    " . $self->Description . "\n";
    for my $line ( @section_lines ) {
	$description .= "    $line\n";
    }
    return $description;
}
#
# END: Class: Parse_error
########################################################################

########################################################################
# Class Section_group
#
package Section_group;
use Carp;

sub new	{
    my $class		= shift;

    my $self = {};
    bless $self, $class;
    return $self;
}

sub Add {
    my $self		= shift;
    my $section		= shift;

    if ( not defined $section ) {
	croak qq(Need to pass in a "Section" object type);
    }

    if ( not $section->isa("Section") ) {
	croak qq(Can only add "Section" object types);
    }

    my $section_class = ref $section;
    ( my $section_type = $section_class )  =~ s/.*:://;

    $section_type = ucfirst lc $section_type;
    $self->$section_type($section);
}

sub Sections {
    my $self		= shift;

    my @sections;
    for my $symbol ( keys %Section_group:: ) {
	next if $symbol ne ucfirst lc $symbol;	# My methods have a particular syntax
	next if $symbol eq "new";	# This is a constructor
	next if $symbol eq "Add";	# Not interested in this method
	next if $symbol eq "Sections";	# This is it's own method
	push @sections, $symbol if $self->can($symbol);
    }

    return wantarray ? @sections : \@sections;
}

sub Group {
    my $self		= shift;
    my $section		= shift;

    if ( defined $section ) {
	push @{ $self->{GROUP} }, $section;
    }
    if ( exists $self->{GROUP} ) {
	my @groups = @{ $self->{GROUP} };
	return wantarray ? @groups : \@groups;
    }
    else {
	return;
    }
}

sub File {
    my $self		= shift;
    my $section		= shift;

    if ( defined $section ) {
	if ( ref $section eq "ARRAY" ) {	# Replacement of current contents
	    $self->{SECTION} = $section;
	} else {
	    push @{ $self->{FILE} }, $section;
	}
    }
    if ( exists $self->{FILE} ) {
	my @files = @{ $self->{FILE} };
	return wantarray ? @files : \@files;
    }
    else {
	return;
    }
}

sub Property {
    my $self		= shift;
    my $section		= shift;

    if ( defined $section ) {
	push @{ $self->{PROPERTY} }, $section;
    }
    if ( exists $self->{PROPERTY} ) {
	my @properties = @{ $self->{PROPERTY} };
	return wantarray ? @properties : \@properties;
    }
    else {
	return;
    }
}

sub Revprop {
    my $self		= shift;
    my $section		= shift;

    if ( defined $section ) {
	push @{ $self->{REVPROP} }, $section;
    }
    if ( exists $self->{REVPROP} ) {
	my @rev_props = @{ $self->{REVPROP} };
	return wantarray ? @rev_props : \@rev_props;
    }
    else {
	return;
    }
}

sub Ban {
    my $self		= shift;
    my $section		= shift;

    if ( defined $section ) {
	push @{ $self->{BAN} }, $section;
    }
    if ( exists $self->{BAN} ) {
	my @bans = @{ $self->{BAN} };
	return wantarray ? @bans : \@bans;
    }
    else {
	return;
    }
}

sub Ldap {
    my $self		= shift;
    my $section		= shift;

    if ( defined $section ) {
	push @{ $self->{LDAP} }, $section;
    }
    if ( exists $self->{LDAP} ) {
	my @ldaps = @{ $self->{LDAP} };
	return wantarray ? @ldaps : \@ldaps;
    }
    else {
	return;
    }
}
#
# END: Class: Section_group
########################################################################

########################################################################
# CLASS Violation
#

package Violation;

sub new {
    my $class		= shift;
    my $file		= shift;
    my $error		= shift;
    my $policy		= shift;

    my $self = {};
    bless $self, $class;

    $self->File($file);
    $self->Error($error);
    $self->Policy($policy);
    return $self;
}

sub File {
    my $self		= shift;
    my $file		= shift;

    if ( defined $file ) {
	$self->{FILE} = $file;
    }
    return $self->{FILE};
}

sub Policy {
    my $self		= shift;
    my $policy		= shift;

    if ( defined $policy ) {
	$self->{POLICY} = $policy;
    }
    return $self->{POLICY};
}

sub Error {
    my $self		= shift;
    my $error		= shift;

    if ( defined $error ) {
	$self->{ERROR} = $error;
    }
    return $self->{ERROR};
}
#
# END: Class: Violations
########################################################################

########################################################################
# POD DOCUMENTATION
#
=pod

=head1 NAME

new-pre-commit-hook.pl

=head1 SYNOPSIS

    new-pre-commit-hook.pl [-file <ctrlFile>] \\
	[-fileloc <cntrlFile>] (-r<revision>|-t<transaction>) \\
	[-parse] [-svnlook <svnlookCmd>] [<repository>]

    new-pre-commit-hook.pl -help

    new-pre-commit-hook.pl -options

=head1 DESCRIPTION

This is a Subversion pre-commit hook that can check for several issues
at once:

=over 2

=item *

This hook can verify that a particular user has permission to change a
file. The file can be specified as either a I<glob> or I<regex> format.
Even better, you can also specify an I<ADD-ONLY> setting that allows you
to create tags via an C<svn copy>, but won't allow you to modify the
files in that directory. This protects tags from being modified by a
user.

=item *

This hook can verify that a particular property has a particular value
and has been set on a particular file. You can specify the files via
I<regex> or I<glob> format, and you can specity the value of the
property either via a I<string>, I<regex>, or I<numeric> value.

=item *

This hook can prevent the user from adding files with banned names. For
example, in Windows you cannot have a file that starts with  C<aux> or
C<prn> or C<con>. You also can't have file names that have C<:>, C<^>,
and several other types of characters in them. You may also want to ban
file names that have spaces in them since these tend to cause problems
with some utilities. This only affects newly added or renamed files, and
not current files.

=item *

This hook can also verify that particular revision properties are set.
However, this only works on Subversion release 1.5 or greater. But,
since Subversion release 1.4 is no longer supported, you really
shouldn't be using releases older than 1.5 anyway.

=back

This hook works through a control file that is in standard Windows
Inifile format (described below). This allows you to set permissions and
other changes without having to modify this program itself.

=head1 OPTIONS

=head2 Control File Definition

The I<Control File> controls the way this hook operates. It can control
the permissions you're granting to various users, your group
definitions, what names are not allowed in your repository, and the
properties associated with the file and revision.

There are two places where the control file can be stored. The first is
inside the Subversion repository server as a physical text file. This
keeps the control file away from prying eyes. Unfortunately, it means
that you must have login access to the repository server in order to
maintain the file.

The other place is inside the repository itself. This makes it easy to
maintain. Plus, since it's in a Subversion repository, you'll see who
changed this file, when, and why. That can be nice for auditing.
Unfortunately, this file will be visible to everyone. If you have an
LDAP password in that file, you'll be exposing that password to all of
your users.

You are allowed to use either a physcial control file, a control file
stored in the repository, or both. You must have at least one or the
other defined.

Format of the control file is discussed below. See L<CONTROL FILE
LAYOUT>

=over 10

=item -file

The location of the physical text control file stored on the Subversion
repository server. Normally, this is kept in the F<hooks> directory
under the Subversion repository directory.

=item -filelocations

The locations of the various control files inside the Subversion
repository. This should use the C<svnlook> format. For exmaple, if you
have a directory called F<control> under the root of your repository,
and inside, your control file is called C<control.ini>, the value of
this parameter would be F</control/control.ini>.

=back

=head2 Other Options

=over 10

=item -r

The Subversion repository revision. Normally, this is only used for
testing purposes since you really want the transaction number of the
commit and not the revision number. Good for testing. This parameter
cannot be used at the same time as the C<-t> parameter.

=item -t

The Subversion repository Transaction Number. This is passed to the
scrip pre-commit found in the Repository's hook directory as a
parameter. You need to modify the pre-commit script to pass the
transaction number to this script.

=item -svnlook

This is the full path to the svnlook command. The full path is needed
because for security reasons, the C<PATH> environment variable is empty
when the hook is executed. Default is /usr/bin/svnlook.

=item -parse

Used mainly for debugging. This will dump out the entire configuration file
structure, so you can verify your work. It will also test the control file
and let you know if there are any errors.

=item -help

Prints a helpful message showing the different parameters used in
running this pre-commit hook script.

=item -documentation

Displays this complete documentation of this hook

=item <repository>

The location of the Subversion repository's physical directory. Default
is the parent directory.

=back

=head1 CONTROL FILE LAYOUT

The hook is controlled by a user defined control file. The control is in
Windows' IniFile layout. This layout consists of I<Comments>, I<Section
Headings>, and I<Parameter Lines>.

=head2 Comments

Comment lines begin with either a C<#>, or a C<;> or a C<'>. Blank lines
are also ignored. All other lines must either be a Parameter Line or a
Section Heading.

=head2 Basic Layout

The basic layout is a Section Heading followed by a bunch of Parameter
Lines.

Section headings are enclosed in square brackets. The first word
in a section heading is the type of section it is (Group, File,
Property, Revprop, or Ban). The rest is a description of that section
heading. For example:

    [File Users may not modify a tag.]

In the above example, the section is I<File> and the description is
I<Users may not modify a tag.>. 

Unlike in L<Config/IniFile>, the descriptions don't have to be unique.
However, the descriptions are used in user error messages, so be sure
to put in a good description that is user friendly. For example:

    [File Only approved users may modify the Control File]

is a better section heading than:

    [File Read-only on Control.properties]

Under each section is a series of Parameter lines that apply to that section.

Parameter Lines are in the form of

    <Key> = <Value>

where I<Key> is the parameter key, and I<Value> is the value for that
parameter. Notice that the two are separated by an equal sign. Spaces
around the equal sign are optional, and the I<Value> is the entire line
including spaces on the end of the line, so be careful.

The layouts of the various sections and their permitted parameters are
explained below. Note that section type names and parameter keys are
case insensitive.

=head3 Group

This is used to define user groups which can be used to define file
permissions. This makes it easier to keep track of file permissions as
people move from project to project. You only have to change the group
definition.

The section layout is thus:

    [GROUP <GroupName>]
    users = <ListOfUsers>

The C<GroupName> is the name of the group. Group names should be
composed of just letters, numbers, and underscores, and should contain
no white space. Group names are case insensitive.

User names in this hook substitute an underscore for a space and ignore case
For example, if the user signs into Subversion as I<john doe>, their user name
will become I<john_doe>. User names cannot start with an I<at sign> (@).

The C<ListOfUsers> is either a whitespace or comma separated list of user
names. This list can also contain the names of other groups. However, the
groups are calculated from the top of the control file to the bottom, so
if group "A" is contained inside group "B", you must define group "A" before
you define group "B".

    [GROUP developers]
    users = larry, moe, curly

    [group admins]
    users = tom, dick, harry

    [group foo]
    users = @developers, @admins, @bar, alice

    [group bar]
    users = bob, ted, carol

In the above example, everyone in group I<DEVELOPERS> and group I<ADMINS>
is in group I<FOO>. However, members of group I<BAR> won't be included.

=head3 File

A file Section Heading starts with the word C<file> and an explanation
of that section. It then consists of the following parameters:

=over 7

=item match

A Perl style expanded regular expression matching the files that are
affected by this permission definition. Note this cannot be used with
the C<file> parameter.

If the C<match> string contains the text E<lt>USERE<gt>, this text
will be substituted by the name of the user from the C<svnlook author>
command. This is done to allow you to create special user directories or
files that only that user can modify. For example:

    [FILE Users can only modify their own watchfiles]
    match = ^/watchfiles/.*
    access = read-only
    users = @ALL

    [FILE Allow user to edit their own watchfiles]
    match = ^/watchfiles/<USER>\.cfg$
    access = read-write
    users = @ALL

The above will prevent users from modifying each other watch files, but
will allow them to modify their own watch files.

B<Word o' Warning>: This script normalizes user ID to all caps. This
means that if the user name is I<bob>, it will become I<BOB>. Thus,
I<< <USER> >> also becomes F<BOB>.


=item file

An Ant style  globbing expression matching the files that are affected
by this permission definition. This cannot be used with the C<match>
parameter.

Regular expressions are much more flexible, but most people are not too
familiar with them. In a file glob expression, an asterisk (*)
represents any number of characters inside of a directory. Double
asterisk (**) are used to represent any number of directory levels. A
single quesion mark (?) represents any character. All glob expressions
are anchored to the front of the line and the back of the line.

Therefore:

    file = *.jpg

does not mean any file that end with C<jpg>, but only files in the root
of the repository that end with C<jpg>. To mean all files, you need to
unanchor the glob expression as thus:

    file = **/*.jpg

Notice too that directory names will end with a final slash which is
a great way to distinguish between a file being added or deleted
and a directory being added or deleted. For example:

    file = /tags/*/

will refer only to directories that are subdirectories directly under the
tags directory, and not to files. You'll see this is a great way to protect
your tagged versions from being modified when L<access> is discussed below.

If the C<file> string contains the text C<E<lt>USERE<gt>>, this text
will be substituted by the name of the user from the C<svnlook author>
command. This is done to allow you to create special user directories or
files that only that user can modify. For example:

    [FILE Users can only modify their own watchfiles]
    file = /watchfiles/**
    access = read-only
    users = @ALL

    [FILE Allow user to edit their own watchfiles]
    file = /watchfiles/<USER>.cfg
    access = read-write
    users = @ALL

The above will prevent users from modifying each other watch files, but
will allow them to modify their own watch files.

=item users

A list of all users who are affected by this type of access. Groups can
be used in a user list if preceeded by an I<at sign> (@). There is one
special group called C<@ALL> that represents all users.

=item access

The access permission on that file. Notice that there is no permission
for preventing a user from seeing the contents of the file, only for
changing the file. This is because the trigger is on the C<commit>
and not on C<checkout>. If you need to prevent people from seeing
the file, you must do this with your repository access.

Access is determined in a top down fashion in the control file. The first
entry might take a particular user's ability to commit changes to a particular
file, but a section further down might allow that same user the ability
to commit changes to that same file. While the third might remove it again.

Access is granted or denied by the B<last> matching access grant.

=over 10

=item read-write

Files marked as C<read-write> means that the user may commit changes to
the file. They can add a new file or directory by that name, delete it, or
modify it.

=item read-only

Files marked as C<read-only> means that the user cannot commit changes to
that file. The user is not allowed to create, delete, or modify this
file.

=item no-delete

Files marked as C<no-delete> allow the user to modify and even create the
file, but not delete the file. This is good for a file that needs to be
modified, but you don't want to be removed.

=item no-add

Files marked as C<no-add> allow the user to modify the file if it already
exists, and are allowed to delete a file if it already exists, but they
are not allowed to add a new file to the repository. This is combined
with the L<no-delete> option above to allow people to modify files, but
not to add new files or delete old ones from the repository.

=item add-only

This is a special access permission that will allow a user to add, but not
modify a file with that matching pattern or regex. This is mainly used to 
ensure that tags may be created but not modified. For example, if you have
a C</tags> directory, you can do this:

    [FILE Users cannot modify any tags]
    file = /tags/**
    access = read-only
    user = @ALL

    [FILE Users can add tags to the tag directory]
    file = /tags/*/
    access = add-only
    user = @ALL

The first L<File> section removes the user's ability to make any changes in
the C</tags> directory. The second L<File> section allows users to only add
directories directly under the C</tags> directory. Thus, a user can do
something like this:

    $ svn cp svn://localhost/trunk svn://localhost/tags/V-1.3

to tag version 1.3 of the source, but then can't modify, add, or delete any
files under the C</tags/V-1.3> directory. Also, users cannot do something
like this:

    $ svn cp svn://localhost/trunk svn://localhost/tags/V-1.3/BOGUS

because the ability to copy a directory is only allowed in the C</tags/>
directory and no subdirectory.

Nor, can a user do this:

    $ touch tags/foo.txt
    $ svn add tags/foo.txt
    $ svn commit -m"Adding a file to the /tags directory"

Since only directories can be added to the C</tags> directory.

=back

=item case

This is an optional parameter and has two possible values: C<match>
and C<ignore>. The default is C<match>. When set to C<ignore>, file name
casing is ignored when attempting to match a file name against the name
of the file that is being committed.

    [file Bob can edit our batch files]
    file = **/*.bat
    access = read-write
    users = bob
    case = ignore

This will match every Batch file with a suffix of I<*.bat> or I<*.BAT> or
even I<*.Bat> and I<*.BaT>.

=back

=head3 Property

This section allows you to set what properties and what those property
values must be on a particular set of files. The section heading looks
like this:

    [property <purpose>]

Where C<purpose> is the purpose of that property. This is used as an
error message if a file fails to have a required property or that
property is set to the wrong value. The following parameters are used:

=over 7

=item match

A Perl style expanded regular expression matching the files that are
affected by this property. Note this cannot be used with the C<file>
parameter.

=item file

A glob type expression matching the files that are affected by this
property. Note this cannot be used with the C<match> parameter.

=item case

An optional parameter and the only permitted value is I<ignore>. This
means to ignore the case of file names (not property values! They're
still case sensitive)

=item property

The name of the property that should be on this file. 

=item value

The value the property should have. Note that this can be either a
string, a number of a regular expression that the value should match.
This is determined by the I<type> parameter.

=item type

The type of value that the I<value> parameter actually contains. This
can be C<string>, C<number>, or C<regex>.

=back

=head3 Revprop

This section allows you to set what revision properties and what
those property values must be when committing a revision.

    [revprop <purpose>]

Where C<purpose> is the purpose of that property. This is used as an
error message if the revision fails to have a required revision property
or that property is set to the wrong value.

The Revision property of C<svn:log> is a special revision property
that all Subversion clients and server versions can use. This is
set by the C<-m> parameter in the C<svn commit> command. This can
be used to verify that the commit log message is in the correct format.

Here is an example:

    [revprop Users must have at least 10 characters of a commit message]
    property = svn:log
    value = ^.{10,}
    type = REGEX

The above requires a user to create an at least 10 character commit
message when committing a change. This will prevent a user from leaving
a null message. You can get even more complex and imaginative:

    [revprop Users must include a Jira ticket number with a commit, or NONE]
    property = svn:log
    value = ^(NONE)|(([A-Z]{3,4}-\d+(,\s+)?)+):.{10,}
    type = REGEX

Imagine you have a ticketing system where ticket numbers start with a three
or four capital letter issue type, followed by a dash, followed by an
issue number (much like Jira). The above will require a user to list
one or more comma separated issue IDs, followed by a colon and a space. If
there is no issue ID, the user can use the word "NONE". This has to
be followed by at least a ten character description. The following
would be valid commit comments:

    NONE: Fixed the indentation of a few files.
    FOO-123: Added a new format to match the specs
    BAR-334, BAZ-349: Fixed the display bug

While the following wouldn't be allowed:

    Fixed stuff
    AAAA
    FOO-123: SSDd

If both the client and server run a release of Subversion 1.5 or
greater, you can use other revision properties on a commit.

Revision properties are set with the C<--with-revprop> on the
C<svn commit> command. Revision properties other than C<svn:log>
can only be used when the Subversion client and server revisions
are 1.5 or newer.

B<WARNING:> Users with a Subversion client older than 1.5
won't be allowed to commit changes if revision properties other
than C<svn:log> are required.

=over 7

=item property

The name of the revision property that should be set in this revision.

=item value

The value the revprop should have. Note that this can be either a
string, a number of a regular expression that the value should match.
This is determined by the I<type> parameter.

=item type

The type of value that the I<value> parameter actually contains. This
can be C<string>, C<number>, or C<regex>.

=back

=head3 Ban

    This section allows you to ban certain file names when you add a new
    file. For example, in Unix, a file can be called C<aux.java>, but
    such a name would be illegal in Windows. 

    The section heading looks like this:

    [ban <description>]

    where E<lt>descriptionE<gt> is the description of that ban. This is
    returned to the user when a banned name is detected.

=over 7

=item match

A Perl style regular expression matching the banned names. Note this
cannot be used with the C<file> parameter.

=item file

An Ant style globbing expression that matches the banned names. Note
this cannot be used with the C<item> parameter.

=item case

This is an optional parameter. If set to I<ignore>, it will ignore the
case in file names.

=back

=head3 Ldap

One of the nice features of this pre-commit hook is that you can use
your LDAP group names as valid groups for the purpose of this hook. If
you are using Windows Active Directory for logins, you can use your
Active Directory server as an LDAP server and your Windows group names
become valid groups for this pre-commit hook.

LDAP requires that the Perl Net::LDAP module be installed. This is an
optional module that can be installed by CPAN. Unfortunately, this must
be done by a system administrator, and the Subversion repository machine
is usually under the control of the System Administration team and not
the Configuration Manager.

Fortunately this is an OPTIONAL module. As long as there is no LDAP
section, this pre-commit hook will work without Net::LDAP being
installed.

The LDAP section header looks like this:

    [ldap <ldapURI or server>]

Where the name of the LDAP server (or full URI can be contained in the
section name. You may include multiple servers.

This allows you to use both the primary LDAP server and possible
secondary servers that are used when the primary is down.

=over 7

=item base

B<REQUIRED>: This is the base DN of the LDAP server. This is a required
parameter, and will look something like this:

    DC=vegicorp,DC=com

I<DC> stands for I<Domain Component>.

=item user_dn

B<OPTIONAL BUT USUALLY REQUIRED>: This is the user's distinguished name
to use to log into the LDAP server. If not given, anonymous access will
be used. Most corporate sites will require some user. This will look
something like:

   DN=CM Admin Account,OU=Special Users,OU=users,DC=vegicorp,DC=com

=item password

B<OPTIONAL BUT USUALLY REQUIRED>: This is the password for the User DN
in order to log into the LDAP server. If not given, the C<user_dn> will
be used, but with no password.  If neither the C<password> or C<user_dn>
are given, anonymous access will be tried.

=item Username_attr

B<OPTIONAL>: This is the name of the attribute that will contain the
user's login name. If you setup your Apache HTTPD server to use LDAP
(and you should), it should be the same attribute you specified there.

This is an optional parameter. The default will be C<sAMAccountName>
which is the default used by Active Directory. Others may be C<mail>,
C<mailNickName>, C<cn> (which would be the full name of the user), and
rarely C<sn> (which is the user's last name).

=item Group_attr

B<OPTIONAL> This is the attribute of the user's LDAP record that
contains all of the groups they are a member of. The user will
automatically be considered a member of all of these groups for the
purpose of this hook.

By default, this is C<memberOf> which is the default for Active
Directory.

=item Search_base

B<OPTIONAL>: This is the base DN for searches. This parameter is
optional, but could speed up the hook because there will be less of the
LDAP tree to search for the particular user. Most LDAP sites are
indexed, and a search for a particular user is usually fairly fast. If
the hook seems slow, try to use the Search_base parameter. Its value
will look something like this:

   OU=users,DC=vegicorp,DC=com

=item Timeout

C<OPTIONAL>: This is the number of seconds to wait for a timeout if the LDAP server
cannot be found. Timing out will cause the pre-commit hook to fail.
However, it can speed up the time it takes for the hook to fail. The
default is currently 5 seconds. Remember this is the maximum time. If
the LDAP server can be found in a few miliseconds, it doesn't matter if
this timeout value is 5 seconds or 100 seconds.

Normally, this should be fine. 5 seconds isn't too long to wait, and if
LDAP is working, it should respond before 5 seconds. However, you can
adjust this value if you have a very slow network.

=back 

=head1 REQUIREMENTS

=head2 Perl Version

This program should work with Perl versions from 5.8.8 and up. It has
been tested with Perl versions 5.8.8, 5.8.9, 5.10, 5.12, 5.14, and 5.18.

=head2 Optional Modules

This program does not require any optional modules. However, if you use
LDAP groups, this program will require Net::LDAP to be installed. This
module may be downloaded from the CPAN repository. 

This module has been tested with Net::LDAP version 0.57.

=head2 Perlbrew

At most companies, the Subversion repository server is controlled by the
System administration team and not the Configuration manager. This means
that the Configuration Manager does not have the ability to install CPAN
modules such as Net::LDAP and requires the cooperation of the System
administration team.

In rare circumstances, the system administration team will refuse to
install I<optional> Perl modules because I<they're not standard>, and
they I<have not been tested>. My first response would be to have these
individuals garroted, lined up in front of a firing squad, shot, and
then fired. Unfortunately, this doesn't help you get the needed Perl
modules installed.

Instead, you will have to conjole and beg. Explain to them that CPAN
modules are tested and used on thousands of sites without any problems.
Most of the time, it is just ignorance on the part of the SA team to
know about Perl, or how CPAN works. Education is your friend.

Another approach is to install a copy of Perl that is under your own
control. You can do this with C<Perlbrew|http://perlbrew.pl>.

Perlbrew allows you to install several non-root version of Perl, and to
easily switch betweent them. I use it to switch between various Perl
versions when I test my hooks and other Perl scripts.

On Linux, Perlbrew requires the developer modules (such as the
compiler) to be installed. On Mac OS X, Perlbrew requires that XCode be
installed, and the various Unix command line utilities. Also make sure
that your C<PATH> includes the Unix command line tools found in
/Applications/Xcode.app/Contents/Developer/usr/bin.

Your System Administrators may let you install Perlbrew just to get you
out of their hair. However, do not break corporate policy by installing
a clandestine copy of Perlbrew and using your own copy of Perl. This
will get you fired (and I would fire you too). The Subversion repository
is usually under tight control and under continous audit. Make sure you
have permission before installing Perlbrew.

=head1 AUTHOR

David Weintraub
L<mailto:david@weintraub.name>

=head1 COPYRIGHT

Copyright (c) 2013 by David Weintraub. All rights reserved. This
program is covered by the open source BMAB license.

The BMAB (Buy me a beer) license allows you to use all code for whatever
reason you want with these three caveats:

=over 4

=item 1.

If you make any modifications in the code, please consider sending them
to me, so I can put them into my code.

=item 2.

Give me attribution and credit on this program.

=item 3.

If you're in town, buy me a beer. Or, a cup of coffee which is what I'd
prefer. Or, if you're feeling really spendthrify, you can buy me lunch.
I promise to eat with my mouth closed and to use a napkin instead of my
sleeves.

=back

=cut

#
########################################################################
