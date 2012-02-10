#! /usr/bin/env perl
#
# pre-commit-kitchensink-hook.pl
########################################################################

########################################################################
# Subversion Pre-Commit Hook
# Even includes the Kitchen Sink
#
# To generate documentation: $ perldoc pre-commit-kitchen-sink-hook.pl
#
########################################################################

########################################################################
# CONSTANTS
#
use constant {
    SVNLOOK_CMD_DEFAULT	   => "/usr/bin/svnlook",
    CONTROL_FILE_DEFAULT   => "./control.ini",
    SVN_REPOSITORY_DEFAULT => "/path/to/repos"
};
#
########################################################################

########################################################################
# USAGE
#
our $USAGE = <<USAGE;
	usage:
	    pre-commit-kitchen-sink-hook.pl [-file <ctrlFile>] \\
		(-r<revision>|-t<transaction>) [-parse]
		[-svnlook <svnlookCmd>] [<repository>]
USAGE
#
########################################################################

########################################################################
# PRAGMAS
#
use strict;
use warnings;
#use feature qw(say);
#
########################################################################

########################################################################
# MODULES
#
use Data::Dumper;
use Getopt::Long;
use Pod::Usage;
#
########################################################################

########################################################################
# GET COMMAND LINE OPTIONS
#
my $svnlookCmd	   = SVNLOOK_CMD_DEFAULT;	#svnlook Command (Full path!)
my $controlFile	   = CONTROL_FILE_DEFAULT;	#Control File
my $svnRepository  = SVN_REPOSITORY_DEFAULT;	#Subversion Repository

my $transaction	 = undef;	#Transaction Number of Repository to examine
my $revision	 = undef;	#Revision Number (for testing)
my $parse	 = undef;	#Parse Control File, but don't run trigger
my $helpFlag	 = undef;	#Display Help?
my $options	 = undef;       #Display detailed help

GetOptions (
    "svnlook=s" =>	\$svnlookCmd,
    "file=s" =>		\$controlFile,
    "t=s" =>		\$transaction,
    "r=i" =>		\$revision,
    "parse" =>		\$parse,
    "help" =>		\$helpFlag,
    "options" =>	\$options,
);

if ($ARGV[0]) {
    $svnRepository = shift;
}

if ($helpFlag) {
    pod2usage(
	{
            -message =>
	    qq(Use "pre-commit-kitchen-sink-hook.pl -options" )
		. qq(to see a detailed description of the parameters),
	    -exitstatus => 0,
	    -verbose    => 0,
	}
    );
}

if ($options) {
    pod2usage( { -exitstatus => 0 } );
}

if (defined($transaction) and defined($revision)) {
    die qq(ERROR: You cannot use both "-r" and "-t" parameters\n);
}

if (not (defined($transaction) or defined($revision))) {
    die qq(ERROR: You must specify either a transaction or revision\n);
}

#
# Append Trans # to svnlook command.
# This way, we don't worry about it later
#

if ($transaction) {
    $revision = " -t$transaction";
} else {
    $revision = " -r$revision";
}
#
########################################################################

########################################################################
# PARSE CONTROL FILE
#

#
# GET COMMIT USER NAME
#

my $command = qq($svnlookCmd author $revision "$svnRepository");
chomp (my $user = qx($command)); #Get User
if ($?) {
    die qq(Can't execute "$command"\n);
}

if ((not $user) and ($parse))  {
    $user = "test-user";	#When parsing, don't let null user blow your day
}
elsif (not $user) {
    die qq(Cannot find user for repository "$svnRepository" ) . 
    qq(Revision $revision\n);
}

#
# CREATE CONTROL FILE OBJECT FOR STORING CONTROL FILE INFO
#

my $configFile = ConfigFile->new($svnRepository, $user, $revision);
$configFile->SvnlookCmd($svnlookCmd);

open(CONTROL_FILE, "$controlFile")
    or die qq(ERROR: Cannot open file "$controlFile" for reading\n);

my $section = undef;			#Not working on a section
my $prevSection = undef;
my %parameterHash = ();
my $lineNum = 0;

#
# NOW PARSE THOUGHT THE ENTIRE CONTROL FILE
#

while (my $line = <CONTROL_FILE>) {
    $lineNum++;
    chomp($line);
    next if ($line =~ /^\s*[#;']/);	#Comments start with "#", ";", or "'"
    next if ($line =~ /^\s*$/);		#Ignore blank lines

    #
    # See if this is a Section Beginning
    #

    if ($line =~ /^\s*\[/) {	#We found a section!
	$section = $line;
	if (defined $prevSection) {
	    $configFile->AddSection($prevSection, \%parameterHash);
	    %parameterHash = ();
	}
	$prevSection = $section;
    }
    elsif ($line =~ /^\s*(\S+)\s*=\s*(.*)/) {	#Parameter
	$parameterHash{$1} = $2;
    }
    else {	#Not Comment, Section, or Paraemter. Invalid Line
	$configFile->AddError(undef, qq(Invalid line "$line" at )
	    . qq(line #$lineNum of Control File));
    }

}
close CONTROL_FILE;

#
# End of Control File: Process the last section and its parameters
#

$configFile->AddSection($prevSection, \%parameterHash);

#
# If the "parse" parameter was present, stop the program and dump out
# the control file structure.
#

if ($parse) {
    print STDERR Dumper($configFile) . "\n";
    exit 2;
}
#
########################################################################

########################################################################
# If there's an LDAP Section, Get LDAP groups
#
my @ldapObjList;
if (@ldapObjList = $configFile->GetSectionType("ldap")) {
    foreach my $ldapObj (@ldapObjList) {
	my @groupList = $ldapObj->GetGroups($configFile->LdapUser);
	foreach my $group (@groupList) {
	    $configFile->AddGroup($group);
	}
    }
}
#
########################################################################

########################################################################
# FIND GROUPS WHERE USER IS A MEMBER AND STORE IN $configFile
#
$user = $configFile->User;
my @memberOfList = ($user, Section::File->AllGroup);
$configFile->AddGroup(Section::File->AllGroup);

foreach my $groupObj ($configFile->GetSectionType("group")) {
    foreach my $user (@memberOfList) {
	if ($groupObj->InGroup($user)) {
	    push @memberOfList, $groupObj->GetGroup;
	    $configFile->AddGroup($groupObj->GetGroup);
	}
    }
}
#
#
########################################################################

########################################################################
# TRIM DOWN NUMBER OF FILE SECTIONS
#
# The only File sections of the Control File that are needed are ones
# where the user or a group where the user is mentioned in is in the
# "users" parameter of the File section. Therefore, we can throw out
# all the File sections where the user is not involved.
#

my $newFileSectionTypeRef = [];	#Store File Sections which concern user
foreach my $fileObject ($configFile->GetSectionType("file")) {
    foreach my $group ($configFile->GetGroups) {
	if (defined ${$fileObject->GetList}{$group}) {
	    push (@{$newFileSectionTypeRef}, $fileObject);
	    last;
	}
    }
}
#
# Replace the File section of the control file with the trimmed down section
#
$configFile->ReplaceSectionType("file", $newFileSectionTypeRef);
#
########################################################################

########################################################################
# PARSE THE CHANGES
#
$command = qq($svnlookCmd changed $revision "$svnRepository");
open (SVN_CHANGE, "$command|")
    or die qq(Can't execute "$command" for reading\n);

while (my $line = <SVN_CHANGE>) { #For each file in the Control file
    chomp $line;
    $line  =~ /^(\w+)\s+(.+)$/;
    my $status = $1;
    my $file = "/" . $2;	#Prepend "/" since its in the control file
    my $errorMsg;

    if ($errorMsg = $configFile->CheckFile($status, $file)) {
	$configFile->AddError(undef, $errorMsg);
    }
    if ($errorMsg = $configFile->CheckBan($status, $file)) {
	$configFile->AddError(undef, $errorMsg);
    }
    if ($errorMsg = $configFile->CheckProperties($status, $file)) {
	$configFile->AddError(undef, $errorMsg);
    }
}
close SVN_CHANGE;
#
########################################################################

########################################################################
# CHECK REVISION PROPERTIES
#
$configFile->CheckRevProp;
#
########################################################################

########################################################################
# SEE IF EVERYTHING IS OKAY
#
if (my @errorList = $configFile->FetchErrors) {
    print STDERR qq(The following issues were discovered. ) .
	qq(Fix them, and rerun "svn commit"\n) . "-" x 72 . "\n";
    foreach my $error (@errorList) {
	print STDERR "$error\n" . "-" x 72 . "\n";
    }
    exit 2;
}
else {
    exit 0;
}
#
# END OF MAIN
########################################################################

#
########################################################################

########################################################################
# PACKAGE ConfigFile
#
# Description:
#    This is a structure that stores the information that is in the
#    control file. It also can store other information important to
#    the processing of this hook.
#
#    The structure contains a place to store the various sections in
#    the control file. This is stored as Section objects. In the
#    area where sections are stored, the sections are divided up into
#    the sub-classses of Section with each class representing a particular
#    section class type. The various section types are sub-classes of the
#    Section class type, and they are stored as an array (list) of 
#    those section sub-class types.
#
#    There is a method called AddSection. This merely calls the new
#    constructor of the Section class and stores this class object
#    representing that section type. (In reality, the Section class
#    constructor #    really calls the constructor of the section type
#    sub-class.)
#
#    EXPANDING THIS CLASS
#
#    If you're adding another section type to the control file, you'll
#    need to add a method in this class to handle checking that type
#    of class. The checking should actually be done in the subclass, but
#    you need the information in this control file.
#
#    You'll also need to add a new Section Sub-class, include
#    "use base qw(Section)" in that subclass to make it a true subclass,
#    and add a VerifySection method.
#
package ConfigFile;
use Data::Dumper;
use Carp;

#------------------------------------------------------------------------
# Constructor:	new
# Description: 	Creates a ConfigFile type to store the ConfigFile Information
# Parameters:
#   $repos:	Directory location of the repository (Optional)
#   $user:	Name of committer (Optional) (Stored normalized)
#   $rev:	Revision number or transaction number (w/ leading -t or -r)
#
# RETURNS:	Class Object
#
sub new {
    my $class	= shift;
    my $repos	= shift;
    my $user	= shift;
    my $rev	= shift;

    my $self = {};
    bless $self, $class;

    $self->Repository($repos);
    $self->User($user);
    $self->Rev($rev);

    return $self;
}

#------------------------------------------------------------------------
# Method:	Repository
# Description:	Adds Repository info to Class, or returns current repos
# Parameters:
#   $repos:	Name of repository (Optional). If given set the repository name
#
# RETURNS:	Name of Repository
#
sub Repository {
    my $self  = shift;
    my $repos = shift;

    if ($repos) {
	$self->{REPOSITORY} = $repos;
    }

    return $self->{REPOSITORY};
}

#------------------------------------------------------------------------
# Method:	User
# Description:	Set or retrieve the name of the committer. This is stored
#               "normalized" which means all upper case, and spaces changed
#               to underscores.
# Parameters:
#   $user:	Name of user (Optional)
#
# RETURNS:	Name of user
#
sub User {
    my $self = shift;
    my $user = shift;

    if (defined $user) {
	$self->LdapUser($user);	#Save original user name for LDAP Query
	$user = uc $user;
	$user =~ s/\s/_/g;
	$self->{USER} = $user;
    }
    return $self->{USER};
}

#------------------------------------------------------------------------
# Method:	LdapUser
# Description:	Set or retrieve the name of the committer. This is stored
#               as retrieved by Ldap which is how the user signed on. The
#               problem is that the user name could contain spaces which
#               can cause problems with this hook. However, if you're
#               using ldap, you need the user name in ldap to find
#               the user's groups.
#               to underscores.
# Parameters:
#   $user:	Name of user (Optional)
#
# RETURNS:	Name of user
#
sub LdapUser {
    my $self = shift;
    my $user = shift;

    if (defined $user) {
	$self->{LDAP_USER} = $user;
    }
    return $self->{LDAP_USER};
}
#------------------------------------------------------------------------
# Method:	Rev
# Description:	Stores the revision number or transaction number. This
#               script assumes you're also storing the -t or -r parameter
#               with the actual revision or transaction number.
# Parameters:
#   $rev:	Revision number (Optional)
#
# RETURNS:	Revision number (with -t/-r parameter as prefix)
#
sub Rev {
    my $self = shift;
    my $rev  = shift;

    if (defined $rev) {
	$self->{REV} = $rev;
    }
    return $self->{REV};
}

#------------------------------------------------------------------------
# Method:	SvnlookCmd
# Description:	Stores and retrieves the svnlook command.
#
# Parameters:
#   $cmd:	The svnlook cammand (optional)
#
# RETURNS:	The svnlook command
#
sub SvnlookCmd {	#Contains Revision/Transaction
    my $self = shift;
    my $cmd  = shift;

    if (defined $cmd) {
	$self->{SVNLOOK} = $cmd;
    }
    return $self->{SVNLOOK};
}

#------------------------------------------------------------------------
# Method:	AddGroup
# Description;	Adds a new group to the Control file that the committer
#               belongs to. This is stored "normalized" (upper case)
# Parameters:
#    $group:	Name of the group
#
# RETURNS:	Undefined
# 
sub AddGroup {
    my $self	= shift;
    my $group	= shift;

    my $user = $self->User;

    if (not defined $self->{GROUP}) {
	$self->{GROUP} = {};
	$self->{GROUP}->{uc $user} = 1;	#User is member of User
    }
    $self->{GROUP}->{uc $group} = 1;
    return undef;
}

#------------------------------------------------------------------------
# Method:	GetGroups
# Description:	Retrieves a Perl list (array) of groups stored by AddGroup
#
# RETURNS:	Perl list (array) of groups

sub GetGroups {
    my $self = shift;

    return keys %{$self->{GROUP}};
}

#------------------------------------------------------------------------
# Method:	AddError
# Description:	Adds an error message that will later be printed out at the
#               of the hook.
# Parameters:
#   $section:	An object of the sub-class of Session type representing
#               that object. Leave as "undef" if not needed
#   $error:	Error message to print.
#
# RETURNS:	undefined
#
sub AddError {
    my $self		= shift;
    my $sectionObject	= shift;
    my $error		= shift;

    if (not defined $self->{ERRORS}) {
	$self->{ERRORS} = [];
    }

    if ($sectionObject) {
	my $sectionName = $sectionObject->SectionName;
	my $sectionType = uc ref($sectionObject);
	$sectionType =~ s/.*:://;
	$error = "Section: $sectionType  - $sectionName:\n   $error";
    }

    push (@{$self->{ERRORS}}, $error);
    return;
}

#------------------------------------------------------------------------
# Method:	FetchErrors
# Descripion:	Fetches the list of stored error messages
#
# Parameters:	None
#
# RETURNS:	List (Array) of error messages.
#
sub FetchErrors {
    my $self = shift;

    if (exists $self->{ERRORS}) {
	return @{$self->{ERRORS}};
    }
    else {
	return;
    }
}

#-----------------------------------------------------------------------
# Method:	AddSection
# Description:	Adds a new Section sub-type class object to the
#               control file record.
# Parameters:
#   $section:	Includes the entire line read in including square brackets
#   $hashRef:	Hash reference of the parameters for the section.
#
# Returns:	Reference to the Section Sub Class Object
#
sub AddSection {
    my $self		= shift;
    my $sectionName	= shift;
    my $sectionHashRef	= shift;


    (my $sectionType = $sectionName) =~ s/^\s*\[\s*(\S+).*$/$1/;
    my $subClass = ucfirst(lc $sectionType);
    my $class = "Section::" . $subClass;

    #
    # Verify Section Type is a Valid Class
    #
    my $section;
    eval {
	$section = $class->new($sectionName, $sectionHashRef);
    };

    # Not a Valid Class
    if ($@) {
	$self->AddError(undef,
	    qq(Invalid Section Type: "$subClass" - "$sectionName"\n));
	return;
    }

    if (not defined $self->{SECTIONS}) {
	$self->{SECTIONS} = {};
    }

    if (not defined $self->{SECTIONS}->{$subClass}) {
	$self->{SECTIONS}->{$subClass} = [];
    }

    push @{$self->{SECTIONS}->{$subClass}}, $section;

    return $section;
}

#------------------------------------------------------------------------
# Method:	GetSectionType
# Description:	Returns a Perl list (array) of Section sub-class objects
#
# Parameters:
#    $section:	Text name of sub-class of Section object ("file", "ban", etc.)
#
# RETURNS:	Perl list (array) of Section sub-class objects
#
sub GetSectionType {
    use Data::Dumper;

    my $self		= shift;
    my $sectionType	= shift;

    if ($self->GetSectionTypeRef($sectionType)) {
	return @{$self->GetSectionTypeRef($sectionType)};
    }
    else {
	return;
    }
}

#------------------------------------------------------------------------
# Method:	GetSectionType
# Description:	Returns a REFERENCE to a Perl list (array) of Section
#               sub-class objects
#
# Parameters:
#    $section:	Text name of sub-class of Section object ("file", "ban", etc.)
#
# RETURNS:	Reference to a Perl list (array) of Section sub-class objects
#
sub GetSectionTypeRef {
    use Data::Dumper;

    my $self		= shift;
    my $sectionType	= shift;

    $sectionType = ucfirst(lc $sectionType); #Should be Perl Class Style

    if (not defined $sectionType) {
	return keys %{$self->{SECTIONS}}; #List of Section Types
    }
    elsif (defined $self->{SECTIONS}->{$sectionType}) {
	return $self->{SECTIONS}->{$sectionType};
    }
    else {
	return;
    }
}

#------------------------------------------------------------------------
# Method:	ReplaceSectionType
# Description:	Replaces the list of section sub-type objects found in 
#               the control file structure. Mainly used for the File
#               sub-type.
#
# Parameteters:
#   $section:	Text name of sub-class type of Section object
#   $refType:	Reference to an array of sub-class type of Section object
#
sub ReplaceSectionType {
    my $self		= shift;
    my $sectionType	= shift;
    my $newTypeRef	= shift;

    $sectionType = ucfirst(lc $sectionType);
    if (not defined $self->{SECTIONS}->{$sectionType}) {
	croak qq("$sectionType" not valid section type);
    }

    $self->{SECTIONS}->{$sectionType} = $newTypeRef;

    return $newTypeRef;
}


#------------------------------------------------------------------------
# Method:	CheckFile
# Description:	Checks whether or not a Section::File object type
#               matches the subversion commit. Only checks added files,
#               and not deleted or modified files.
# Parameters:
#   $status:	The status of the file being added. First two characters of
#               the subversion change log report on the commit
#   $file:	File being checked
#
#   RETURN:	Returns null on success or text message on failure.
#
sub CheckFile {
    my $self		= shift;
    my $status		= shift;
    my $file		= shift;

    use constant {
	PERMITTED	=> 1,
	NOT_PERMITTED	=> 0,
	READ_ONLY	=> "RO",
	READ_WRITE	=> "RW",
	ADD_ONLY	=> "AO",
	NO_DELETE	=> "ND",
	IGNORE_CASE	=> "ignore",
    };

    
    my $permission = PERMITTED;		#Assume Operation is Allowed

    my $sectionPurpose;
    foreach my $fileObject ($self->GetSectionType("file")) {
	my $access = $fileObject->GetAccess;
	my $regex  = $fileObject->GetMatch;
	my $case   = uc $fileObject->GetCase;

	if ($file =~ /$regex/
		or ($case eq uc(IGNORE_CASE) and $file =~ /$regex/i)) {
	    if ($access eq READ_ONLY) {
		$permission = NOT_PERMITTED;
		$sectionPurpose = $fileObject->SectionPurpose;
	    }
	    elsif ($access eq READ_WRITE) {
		$permission = PERMITTED;
	    }
	    elsif ($access eq NO_DELETE and $status =~ /^D/) {
		$permission = NOT_PERMITTED;
		$sectionPurpose = $fileObject->SectionPurpose;
	    }
	    elsif ($access eq ADD_ONLY) {
		if ($status =~ /^A/) {
		    $permission = PERMITTED;
		}
		else {
		    $permission = NOT_PERMITTED;
		    $sectionPurpose = $fileObject->SectionPurpose;
		}

	    }
	}
    }
    if ($permission != PERMITTED) {
	return qq("$file": No permission to commit this file\n$sectionPurpose);
    } 
    return;	#Succeeded
}

#------------------------------------------------------------------------
# Method:	CheckBan
# Description:	Checks whether or not a Section::Ban object type
#               matches the subversion commit. Only checks added files,
#               and not deleted or modified files.
# Parameters:
#   $status:	The status of the file being added. First two characters of
#               the subversion change log report on the commit
#   $file:	File being checked
#
#   RETURN:	Returns null on success or text message on failure.
#
sub CheckBan {
    my $self	= shift;
    my $status	= shift;
    my $file	= shift;

    use constant {
	IGNORE_CASE => "ignore",
    };

    return unless($status eq "A");	#Only check newly added files

    foreach my $banObject ($self->GetSectionType("ban")) {
	my $regex = $banObject->GetMatch;
	my $case  = uc $banObject->GetCase;
	if ($file =~ /$regex/
		or ($case eq uc(IGNORE_CASE) and $file =~ /$regex/i)) {
	    my $reason = $banObject->SectionPurpose;
	    return qq(Banned File name: "$file" - $reason);
	}
    }
    return;
}

#------------------------------------------------------------------------
# Method:	CheckProperties
# Description:	Checks whether or not a Section::Properties object type
#               matches the subversion commit.
# Parameters:
#   $status:	The status of the file being added. First two characters of
#               the subversion change log report on the commit
#   $file:	File being checked
#
#   RETURN:	Returns null on success or text message on failure.
#
sub CheckProperties {
    my $self 	= shift;
    my $status	= shift;
    my $file	= shift;

    use constant {
	IGNORE_CASE => "ignore",
    };

    #
    # Can't Check Properties on Deleted files!
    #

    return if ($status =~ /^d/i);

    #
    # Need these to find the properties
    #
    my $svnlook = $self->SvnlookCmd;
    my $repos   = $self->Repository;
    my $rev	= $self->Rev;

    my %propHash;	#Properties that file currently has
    $command = qq($svnlookCmd proplist $rev "$repos" "$file");
    open (PROPLIST, "$command|")
	or croak qq(Can't execute command "$command" for reading);

    while (my $property = <PROPLIST>) {
	chomp $property;
	$property =~ s/^\s*//;
	$propHash{$property} = 1;
    }
    close PROPLIST;

    foreach my $propObject ($self->GetSectionType("property")) {
	my $regex = $propObject->GetMatch;
	next unless ($file =~ /$regex/);

	my $reqProp  = $propObject->GetProperty;
	my $reqValue = $propObject->GetValue;
	my $type     = $propObject->GetType;
	my $case     = $propObject->GetCase;
	my $reason   = $propObject->SectionPurpose;

	if (not exists $propHash{$reqProp}) {
	    $self->AddError(undef,
		qq(Missing property "$reqProp" for "$file"\n$reason));
	    next;
	}

	my $propValue;
	$command = qq($svnlookCmd propget $rev "$repos" "$reqProp" "$file");
	$propValue = qx($command);
	chomp $propValue;
	if ($type eq "S" and  $propValue ne $reqValue) {
	    $self->AddError(undef,
		qq($file: Prop. "$reqProp" must equal "$reqValue"\n$reason));
	}
	elsif ($type eq "R") {
	    if ($propValue !~ /$reqValue/
		or ($propValue !~ /$reqValue/ and $case eq uc IGNORE_CASE)) {
		$self->AddError(undef,
		    qq($file: Prop "$reqProp" ) 
			. qq(must match regex /$reqValue/\n$reason));
	    }
	}
	elsif ($type eq "I" and  $propValue != $reqValue) {
	    $self->AddError(undef,
		qq($file: Prop. "$reqProp" must equal "$reqValue"\n$reason));
	}
    }
}

#------------------------------------------------------------------------
# Method:	CheckRevProps
# Description:	Checks whether or not a Section::Revprops object type
#               matches the subversion commit.
# Parameters:
#   $status:	The status of the file being added. First two characters of
#               the subversion change log report on the commit
#
#   RETURN:	Returns null on success or text message on failure.
#
sub CheckRevProp {
    my $self 	= shift;

    my $rev	   = $self->Rev;
    my $repository = $self->Repository;
    my $svnlookCmd = $self->SvnlookCmd;

    #
    # Get Listing of Revision properties
    #

    my $command = qq($svnlookCmd proplist $rev --revprop "$repository");
    open (PROPLIST, "$command|")
	or croak qq(Cannot open command "$command" for reading);

    my %revpropHash;
    while (my $property = <PROPLIST>) {
	chomp $property;
	$property =~ s/^\s+//;
	$revpropHash{$property} = 1;
    }
    close PROPLIST;

    foreach my $revPropObj ($self->GetSectionType("revprop")) {
	my $reqProp  = $revPropObj->GetProperty;
	my $reqValue = $revPropObj->GetValue;
	my $type     = $revPropObj->GetType;
	my $propValue;
	my $reason = $revPropObj->SectionPurpose;

	if (not defined $revpropHash{$reqProp}) {
	    $self->AddError(undef, qq(Missing required revprop "$reqProp"\n$reason));
	    next;
	}

	if ($reqProp eq "svn:log") {
	    $propValue = qx($svnlookCmd log $rev "$repository");
	} else {
	    $propValue = qx($svnlookCmd propget $rev )
		. qq(--revprop "$repository" "$reqProp");
	}

	chomp $propValue;
	if ($type eq "S" and  $propValue ne $reqValue) {
	    $self->AddError(undef, qq(Revprop "$reqProp" ) 
		. qq(must equal "$reqValue"\n$reason));
	}
	elsif ($type eq "R" and $propValue !~ /$reqValue/) {
	    $self->AddError(undef, qq(Revprop "$reqProp" must match ) 
		. qq(regex /$reqValue/\n$reason));
	}
	elsif ($type eq "I" and  $propValue != $reqValue) {
	    $self->AddError(undef, qq(Revprop "$reqProp" must equal )
		. qq("$reqValue"\n$reason));
	}
    }
}

########################################################################
# PACKAGE Section
#
# Description:
#    This is a super class for all of the various Section sub-classes.
#    This class does most of the functions, including creating a new
#    type, retrieving the parameters in that type, etc.
#
#    The sub-classes of this super type must include a VerifySection
#    method since the VerifySection method of this super type merely calls
#    the VerifySelection method of the sub-class. However, the sub-classes
#    may have their own methods.
#
package Section;
use Carp;

#------------------------------------------------------------------------
# Constructor:	new
# Description:	Creates a new Section sub-class object.
#
# Parameters:
#    $section:	Section name. Includes the entire name and is used for
#               deriving the sub-class object type. Should include
#               the entire section heading from the Ini file including
#               the square brackets
#   $hashRef	The parameter hash reference from the control file.
#
sub new {
    my $class		= shift;
    my $sectionName	= shift;
    my $sectionHashRef	= shift;

    (my $subClass = $class) =~ s/.*:://;
    my $self = {};
    bless $self, $class;
    $self->SectionName($sectionName);
    my $newHashRef = $self->HashRef($sectionHashRef);
    $self->VerifySection($configFile, $newHashRef);

    return $self;
}

#------------------------------------------------------------------------
# Method:	SectionName
# Description:  Sets or returns the section name. Really sub-class object.
#
# Parameters:
#    $section:  Entire line from the INI file incl. square brackets (Optional)
#
# RETURNS:	Section Name
#
sub SectionName {
    my $self		= shift;
    my $sectionName	= shift;

    if (defined $sectionName) {
	$self->{SECTION_NAME} = $sectionName;
    }
    return $self->{SECTION_NAME};
}

#------------------------------------------------------------------------
# Method:	SectionPurpose
# Description:	Returns the "Purpose" of a section
# Parameters:	None
#
# RETURNS:	Section Name minus the first word and braces
#
sub SectionPurpose {
    my $self	= shift;

    my $sectionName = $self->SectionName;
    (my $purpose = $sectionName) =~ s/\s*\[\s*\S+\s*(.*)\s*\]\s*/$1/;
    return $purpose;
}


#------------------------------------------------------------------------
# Method:	Section Type
# Description:	Returns the sub-class of the Section super class
#
# Parameters:	none
# RETURNS:	text string of object sub-class type
sub SectionType {
    my $self = shift;

    my $class = ref($self);
    (my $subClass = $class) =~ s/.*:://;

    return $subClass;
}

#------------------------------------------------------------------------
# Method:	HashRef
# Description:	This is a sub-class object of the Section super class, This
#               will set the parameter Hash in the Section Subclass. The
#               keys of the hash will be stored in upper case. This will
#               both set and/or return the hash reference of the parameters
# Parameters:
#   $hashRef:	The hash reference representing the parameters for that section.
#
# RETURNS:	Hash reference of the parameters for the section sub-class.
#
sub HashRef {
    my $self	= shift;
    my $hashRef = shift;

    if (defined $hashRef) {
	#
	# Make Hash Elements Uppercase
	#
	my %origHash = %{$hashRef};
	my %newHash;

	foreach my $oldKey (keys %origHash) {
	    my $newKey = uc($oldKey);
	    $newHash{$newKey} = $origHash{$oldKey}
	}
	$self->{HASH_REF} = \%newHash;
    }
    return $self->{HASH_REF};
}

#------------------------------------------------------------------------
# Method:	VerifySection
# Description:	Calls the sub-class's VerifySection method. This method 
#               is suppose to verify that the sub-type section class object
#               for this method is good. This usually means verifying the
#               parameters -- making sure all required parameters are there.
#               The sub-classes VerifySection parameter is also used to
#               munge the hash. For example, the Section::File VerifySection
#               method will take a glob in the "file" parameter, and translate
#               it into a regular expression, then create a "match" parameter.
#		Some of these will take a "user" parameter which list users
#		and turn it into a keyed hash with each user as a key. This
#		makes it easier and faster to check whether a user is in the
#		user parameter list.
# Parameters:
#   $config:	The configFile object type's object reference. Needed to call
#               the Config File's "AddError" method.
#   $hashRef:	A hash reference of the parameters to verify for that sub-class'
#               object type.
#
sub VerifySection {
    my $self		= shift;
    my $configFile	= shift;
    my $hashRef		= shift;

    my $sectionType = ref($self);

    $sectionType->Verify($configFile, $hashRef);
    return $self;
}

#------------------------------------------------------------------------
# Method:	Glob2Regex
# Description:	Takes an Ant style file glob and turns it into a regular
#               expression. This allows me to simply use the regular expression
#               even if the config file defined a file glob to match against the
#               file. This is a sub-class method of the Section superclass.
# Parameters:
#    glob:	The file glob to convert.
#
# RETURNS:	The regular expression of the file.
#
sub Glob2Regex {
    my $self = shift;
    my $glob = shift;

    my $regex = undef;
    my $previousAstrisk = undef;

    foreach my $letter (split(//, $glob)) { #Check if previous was astrisk
	if ($previousAstrisk) {
	    if ($letter eq "*") { #Double astrisk
		$regex .= ".*";
		$previousAstrisk = undef;
		next;
	    } else {	#Single astrisk: Write prev match
		$regex .= "[^/]*";
		$previousAstrisk = undef;
	    }
	}
	if ($letter =~ /[\{\}\.\+\(\)\[\]]/) { #Quote all Regex metacharaters
	    $regex .= "\\$letter";
	} elsif ($letter eq "?") { #Translate Glob "?" to Regex
	    $regex .= ".";
	} elsif ($letter eq "*") { #Is this "*" or "**": Don't translate now
	    $previousAstrisk = 1;
	} elsif ($letter eq '\\') { # Make backslash for file forward slash
	    $regex .= "/";
	} else {	#No special Glob symbol
	    $regex .= $letter;
	}
    }
    #
    #   ####Handle if last letter was astrisk
    #
    if ($previousAstrisk) {
	$regex .= "[^/]*";
    }
    $regex = "^$regex\$"; #Globs are anchored to start and end of string
    return $regex;
}

#------------------------------------------------------------------------
# Method:	GetAttribute
# Description:	This method returns the attribute value of the parameters
#               for the sub-class of the Section super-class.
# Parameters:
#    $attr:	A string scalar attribute of the Section sub-class.
#               (For example, "file" for a Section::File class object)
#
# RETURNS:	attribute value.
#
sub GetAttribute {
    my $self 	  = shift;
    my $attribute = shift;

    if (defined $self->{HASH_REF}->{uc $attribute}) {
	return $self->{HASH_REF}->{uc $attribute};
    }
    else {
	return;
    }
}

#------------------------------------------------------------------------
# Method:	GetAttributeHash
# Class:	Sub class of Section Superclass
# Description:	Returns a hash listing all of the attributes for 
#               the object.
#
# RETURNS:	A Perl hash of the parameters for that sub-class. Keyed
#               by attribute and contains the attribute value.
#
sub GetAttributeHash {
    my $self = shift;

    return %{$self->{HASH_REF}};
}

#------------------------------------------------------------------------
# AUTOLOAD
#
# This AUTOLOAD creates a front end to the GetAttribute method. This
# allows you to create a method with the name of the parameter of the
# object type. For example, File::Section->GetMatch will return the
# value of the MATCH parameter for that particular File::Section.
#
# $object->GetXxxxx = $object->GetAttribute("xxxxx");
#
sub AUTOLOAD {
    my $self =  shift;

    our $AUTOLOAD;

    (my $subClass = $AUTOLOAD) =~ s/.*:://;

    if ((my $attribute = $subClass) =~ s/^Get//) {
	return $self->GetAttribute($attribute);
    }
    croak qq(Non existant subroutine called $AUTOLOAD);
}
#
########################################################################

########################################################################
# PACKAGE Section::Group
#
package Section::Group;
use base qw(Section);

use Data::Dumper;

use constant {
    USERS => "users",
    GROUP => "group",
    LIST  => "list",
};

#------------------------------------------------------------------------
# Method:	VerifySection
# Description:  This verifies a Section::Group. It creates two extra
#               parameters:
#               LIST:	A hash keyed by all users in this group
#               GROUP:	The name of the group stripped from the SectionName
#
sub VerifySection {
    my $self		= shift;
    my $configFile	= shift;
    my $hashRef		= shift;

    my %hash		= %{$hashRef};	#Dereference Hash

    foreach my $required (USERS) {
	if (not exists $hash{uc $required}) {
	    my $error = "Missing parmeter $required";
	    $configFile->AddError($self, $error);
	}
    }

    #
    # Add Group Name as Parameter
    #

    (my $groupName = uc $self->SectionName) =~ s/^\S+\s+(.*)\s*\]/$1/;
    $groupName = "@" . $groupName;
    $hashRef->{uc GROUP} = $groupName;

    #
    # Add List as Parameter
    #

    if (not defined $hashRef->{uc LIST}) {
	$hashRef->{uc LIST} = {};
    }

    foreach my $user (split /\s+|\s*,\s*/, $hashRef->{uc USERS}) {
	$hashRef->{uc LIST}->{uc $user} = 1;
    }

    return $self;
}

#------------------------------------------------------------------------
# Method:	InGroup
# Description:	Checks to see if the user is in a particular group
#
# Parameters:
#    $user:	String scalar of user name.
#
# RETURNS:	Normalized name of user if it is in the group. Undef otherwise.
#
sub InGroup {
    my $self =	shift;
    my $user =	shift;

    my %userHash = %{$self->GetAttribute(LIST)};
    if (exists $userHash{uc $user}) {
	return uc $user;
    }
    else {
	return;
    }
}
#
########################################################################

########################################################################
# Package Section::File
#
package Section::File;
use base qw(Section);

use constant {
    REGEX	=> "match",
    GLOB	=> "file",
    ACCESS	=> "access",
    USERS	=> "users",
    LIST	=> "list",
};

use constant {
    USER_REGEX => "<USER>",
};

use constant {
    ACCESS_READ		=> "read-only",
    ACCESS_WRITE	=> "read-write",
    ACCESS_ADD		=> "add-only",
    ACCESS_NO_DELETE	=> "no-delete",
    ALL_GROUP		=> "ALL",
};

#------------------------------------------------------------------------
# Method:	AllGroup
# Description:	Returns the name of the AllGroup
#
# RETURNS:	Text name of ALL group.
sub AllGroup {
    if (ALL_GROUP !~ /^\@/) {
    return "@" . uc ALL_GROUP;
    }
    else {
	return uc ALL_GROUP;
    }
}

#------------------------------------------------------------------------
# Method:	VerifySection
# Description:  This verifies a Section::File. It creates two extra
#               parameters:
#               LIST:	A hash keyed by all users in this object
#               REGEX:	Value of converted GLOB parameter
#
sub VerifySection {
    my $self		= shift;
    my $configFile	= shift;
    my $hashRef 	= shift;

    my %hash		= %{$hashRef};

    foreach my $required (ACCESS, USERS) {
	if (not exists $hash{uc $required}) {
	    my $error =  "Missing parmeter $required";
	    $configFile->AddError($self, $error);
	}
    }

    $hashRef->{uc USERS} = uc $hashRef->{uc USERS}; #User name is uppercase
    my $access = uc $hashRef->{uc ACCESS};

    if ($access eq uc ACCESS_READ) {
	$hashRef->{uc ACCESS} = "RO";
    }
    elsif ($access eq uc ACCESS_WRITE) {
	$hashRef->{uc ACCESS} = "RW";
    }
    elsif ($access eq uc ACCESS_ADD) {
	$hashRef->{uc ACCESS} = "AO";
    }
    elsif ($access eq uc ACCESS_NO_DELETE) {
	$hashRef->{uc ACCESS} = "ND";
    }
    else {
	$configFile->AddError($self, qq(Invalid file access "$access"));
    }

    if (exists $hash{uc REGEX} and exists $hash{uc GLOB}) {
	my $error = qq(Can't have both "@{[REGEX]}" and "@{[GLOB]}" )
	    . qq(parameters at same time.);
	$configFile->AddError($self, $error);
    }
    elsif (not exists $hash{uc REGEX} and not exists $hash{uc GLOB}) {
	my $error = qq(Must have either a "@{[REGEX]}" or "@{[GLOB]}" )
	    . qq(parameter.);
	$configFile->AddError($self, $error);
    }

    #
    # If this is Glob, create Regex for it
    #
    if (exists $hash{uc GLOB}) {
	my $glob = $hashRef->{uc GLOB};
	my $regex = $self->Glob2Regex($glob);
	$hashRef->{uc REGEX} = $regex;
    }

    #
    # Special Case: Change USER string to User's Name
    #

    my $user = $configFile->User;
    my $userString = USER_REGEX;
    my $fileRegex = $hashRef->{uc REGEX};
    $fileRegex =~ s/$userString/$user/;
    $hashRef->{uc REGEX} = $fileRegex;

    #
    # Create Users List
    #
    
    if (not defined $hashRef->{uc LIST}) {
	$hashRef->{uc LIST} = {};
    }

    foreach my $user (split /\s+|\s*,\s*/, $hashRef->{uc USERS}) {
	$hashRef->{uc LIST}->{uc $user} = 1;
    }
}
#
########################################################################

########################################################################
# PACKAGE Section::Property
#
package Section::Property;
use base qw(Section);

use constant {
    REGEX	=> "match",
    GLOB	=> "file",
    PROPERTY	=> "property",
    VALUE	=> "value",
    TYPE 	=> "type",
};

use constant {
    TYPE_STRING		=> "string",
    TYPE_REGEX		=> "regex",
    TYPE_NUMBER		=> "numeric",
};

#------------------------------------------------------------------------
# Method:	VerifySection
# Description:  This verifies a Section::Property. It creates one extra
#               parameter:
#               REGEX:	Value of converted GLOB parameter
#
sub VerifySection {
    my $self 		= shift;
    my $configFile	= shift;
    my $hashRef		= shift;

    my %hash		= %{$hashRef};

    foreach my $required (PROPERTY, TYPE, VALUE) {
	if (not exists $hash{uc $required}) {
	    my $error = "Missing parameter $required";
	    $configFile->AddError($self, $error);
	}
	if ($required eq TYPE) {
	    my $value = uc $hash{uc TYPE};
	    $hashRef->{uc TYPE} = $value;	#All type values are uppercase
	    if ($value eq uc TYPE_STRING) {
		$hashRef->{uc TYPE} = "S";
	    }
	    elsif ($value eq uc TYPE_REGEX) {
		$hashRef->{uc TYPE}= "R";
	    }
	    elsif ($value eq uc TYPE_NUMBER) {
		$hashRef->{uc TYPE} = "I";
	    }
	    else {
		$configFile->AddError($self, qq(Invalid type "$value"));
	    }
	}
    }
    if (not exists $hash{uc REGEX} and not exists $hash{uc GLOB}) {
	$configFile->AddError($self, qq(Must have parameter of "@{[REGEX]}" )
	    . qq(or "@{[GLOB]}"));
    }
    if (exists $hash{uc REGEX} and exists $hash{uc GLOB}) {
	$configFile->AddError($self, qq(Must only have one parameter of )
	    . qq("@{[REGEX]}" or "@{[GLOB]}"));
    }

    #
    # If this is Glob, create Regex for it
    #
    if (exists $hash{uc GLOB}) {
	my $glob = $hashRef->{uc GLOB};
	my $regex = $self->Glob2Regex($glob);
	$hashRef->{uc REGEX} = $regex;
    }
}
#
########################################################################

########################################################################
# PACKAGE Section::Ban
#
package Section::Ban;
use base qw(Section);

#------------------------------------------------------------------------
# Method:	VerifySection
# Description:  This verifies a Section::Ban. It creates one extra
#               parameter:
#               REGEX:	Value of converted GLOB parameter
#
sub VerifySection {
    my $self 		= shift;
    my $configFile	= shift;
    my $hashRef		= shift;

    my %hash = %{$hashRef};

    if (exists $hash{MATCH} and exists $hash{FILE}) {
	my $error = qq(Can't have both "MATCH" and "FILE" parameters )
	    . qq(at same time.);
	$configFile->AddError($self, $error);
    }
    elsif (not exists $hash{MATCH} and not exists $hash{FILE}) {
	my $error = qq(Must have a "MATCH" or "FILE" parameter.);
	$configFile->AddError($self, $error);
    }
}
#
########################################################################

########################################################################
# PACKAGE Section::Revprop
#
#------------------------------------------------------------------------
# Method:	VerifySection
# Description:  This verifies a Section::Revprop.
#
package Section::Revprop;
use base qw(Section);

use constant {
    PROPERTY	=> "property",
    VALUE	=> "value",
    TYPE 	=> "type",
};

use constant {
    TYPE_STRING		=> "string",
    TYPE_REGEX		=> "regex",
    TYPE_NUMBER		=> "numeric",
};

sub VerifySection {
    my $self 		= shift;
    my $configFile 	= shift;
    my $hashRef		= shift;

    my %hash = %{$hashRef};

    foreach my $required (PROPERTY, VALUE, TYPE) {
	if (not exists $hash{uc $required}) {
	    my $error = "Missing parameter $required";
	    $configFile->AddError($self, $error);
	}
	if ($required eq TYPE) {
	    my $value = uc $hash{uc TYPE};
	    $hashRef->{uc TYPE} = $value;	#All type values are uppercase
	    if ($value eq uc TYPE_STRING) {
		$hashRef->{uc TYPE} = "S";
	    }
	    elsif ($value eq uc TYPE_REGEX) {
		$hashRef->{uc TYPE}= "R";
	    }
	    elsif ($value eq uc TYPE_NUMBER) {
		$hashRef->{uc TYPE} = "I";
	    }
	    else {
		$configFile->AddError($self, qq(Invalid type "$value"));
	    }
	}
    }
}
#
########################################################################

########################################################################
# PACKAGE Section::Ldap
#
package Section::Ldap;
use base qw(Section);
use Carp;
use Data::Dumper;

#
# Verify that the Net::LDAP module is available before you do
# "use Net::LDAP". I don't want to have the program die just because
# that module isn't available unless there's an Ldap section of the
# Configuration File. The package variable NetLdapStatus will be true
# if the module is available.
#
# NOTE: $NetLdapStatus is a PACKAGE variable, thus once set by this,
#       it will be available to all methods in this package. So, don't
#       get freaked out when you see it used without being initialized
#       by anything in that method.
#
BEGIN {
    eval { require Net::LDAP; };
    our $NetLdapStatus  = 1 if (not $@);
}

#------------------------------------------------------------------------
# Method:	NetLdapStatus
# Description:	Tells you whether the Perl module Net::LDAP is installed
#
# RETURNS:	True if Net::LDAP is installed. Otherwise false.
#
sub NetLdapStatus {
    our $NetLdapStatus;
    return $NetLdapStatus;
}

sub VerifySection {
    my $self		= shift;
    my $configFile	= shift;
    my $hashRef		= shift;

    my %hash = %{$hashRef};
    if (not $self->NetLdapStatus) {
	print STDERR  qq(Missing "Net::LDAP" Perl module. ) . 
	    qq(Can't use LDAP section in Control File);
	exit 2;
    }

    #
    # Add LDAP URL to HashReference
    #

    (my $sectionName = $self->SectionName) =~ /\[\s*\S+\s+(\S+)\s*\]/;
    my $ldapUrl = $1;
    $hashRef->{URL} = $ldapUrl;
    
    foreach my $required (qw(groupAttr filter regex)) {
	if (not exists $hash{uc $required}) {
	    my $error = "Missing parameter $required";
	    $configFile->AddError($self, $error);
	}
    }
}

sub GetGroups {
    my $self = shift;
    my $user = shift;	#LDAP User

    #
    # Get all of the options for Ldap
    #

    my %constructorHash;	#Constructor (new) options
    my %bindHash;		#Bind Method options
    my %searchHash;		#Search Method options
    my %getHash;		#Get Method options


    my %attributeHash = $self->GetAttributeHash;
    foreach my $key (keys %attributeHash) {
	if ($key =~ /^ldap:(.*)/i) {
	    $constructorHash{$1} = $self->GetAttribute($key);
	}
	elsif ($key =~ /^bind:(.*)/i) {
	    $bindHash{lc $1} = $self->GetAttribute($key);
	}
	elsif ($key =~ /^search:(.*)/i) {
	    $searchHash{lc $1} = $self->GetAttribute($key);
	}
	elsif ($key =~ /^get:(.*)/i) {
	    $getHash{lc $1} = $self->GetAttribute($key);
	}
    }
    #
    # Run Constructor
    # 

    $constructorHash{onerror} = undef; 	#Let LDAP Croak sn any errors;
    my $ldap = Net::LDAP->new($self->GetUrl, %constructorHash);

    #
    # Bind to LDAP URL
    #

    my $message;
    if (not $self->GetBind) {		#Anonymous Bind: No options at all
	$message = $ldap->bind;
    }
    elsif (not keys %bindHash) {  	#Bind DN, but no options
	$message = $ldap->bind($self->GetBind);
    }
    else {
	$message = $ldap->bind($self->GetBind, %bindHash);
    }
    if ($message->code != 0) {
	croak qq(Can't bind LDAP: ) . $message->error_desc;
    }

    #
    # Run Search Query
    #

    $searchHash{filter} = $self->GetFilter . "=" . $user;
    my $results = $ldap->search(%searchHash);
    if (not $results->entries) {
	return;		#Not an LDAP Account
    }

    #
    # Get Results (An array, but we're only interested in the first entry
    #
    
    my $entry  = $results->pop_entry;
    my @groups = $entry->get_value($self->GetGroupattr);
    my $regex  = $self->GetRegex;

    #
    # Return list of groups, but you'll have to munge the return
    # Use "map" to apply regex to group to pull out group name from DN
    #
    if (scalar @groups and defined $regex) {
	return map { m/$regex/; $_ = "@" . $1; s/\s+/_/g; $_; } @groups;
    }
    else {
	return;
    }
}
#
########################################################################

########################################################################
# POD DOCUMENTATION
#
=pod

=head1 NAME

pre-commit-kitchensink-hook.pl

=head1 SYNOPSIS

    pre-commit-kitchen-sink-hook.pl [-file <ctrlFile>] \\
	(-r<revision>|-t<transaction>)
	[-svnlook <svnlookCmd>] [<repository>]

    pre-commit-kitchen-sink-hook.pl -help

    pre-commit-kitchen-sink-hook.pl -options

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

=over 10

=item -file

The I<Control File> used for verifying the Subversion pre-commit
transaction. The default is C<control-file.ini> in the repository
hook directory. The control file layout is given below.

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

=item -help

Prints a helpful message showing the different parameters used in
running this pre-commit hook script.

=item -options

Prints a helpful message showing a detailed explanation of  the
different parameters used in running this pre-commit hook script.

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
will become I<JOHN_DOE>. User names cannot start with an I<at sign> (@).

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

Files marked as <no-delete> allow the user to modify and even create the
file, but not delete the file. This is good for a file that needs to be
modified, but you don't want to be removed.

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

This is an optional parameter and its only valid value is I<ignore>. This
allows you to ignore case when looking at file names. For example:

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

Imagine you have a ticketin system where ticket numbers start with a three
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

This section defines an LDAP server for the purposes of pulling of LDAP
groups to use in this hook. For example, if you have a Windows Active
Directory server, you could use your Windows groups to put users into
groups for this particular hook.

Due to the complexities of the LDAP query and the wide variety used by
various groups, it is somewhat necessary to play loose and fast with the
way attributes work.

The section heading will look like this:

    [ldap <ldapURI or server>]

Where the name of the LDAP server (or full URI can be contained in the
section name.

=over 7

=item ldap:xxxxx

This allows you to further define how to do ldap binding. The "xxxx" is
the option in the Net::LDAP constructor. For example, C<ldap:scheme> will
be the I<scheme> option in the Net::LDAP constructor. The most common ones
are:

=over 2

=item * ldap:password

The password for the ldap server

=item * ldap:scheme

This could be F<ldap> or F<ldaps>

=item * ldap:port

The port number for LDAP.

=back

=item bind

The I<Distinguished Name> used by the LDAP server for I<binding>
(logging in) to the ldap server. If not given, anonymous binding will be
done.

=item bind:xxxx

This is an option used in the F<bind> method in the L<Net::LDAP> class.
The most common ones are:

=over 2

=item * bind:password

The password for the Distinguish name.

=back

=item filter

This is the attribute you are filtering on via the Ldap name of the
user. In Windows Active Directory, this is usually something like
C<sAMAccountName>.

This is used by the I<search> method of the Net::LDAP module. For
example, let's say that you've filtered on C<sAMAccountName> for Ldap
user C<johnsmith>. The call to the Net::LDAP search method will
look something like this:

    my $search = $ldap->search(filter => "sAMAccountName=johnsmith");

=item search:xxxxxx

Other attributes to use for the search method. Common ones are

=over 2

=item * search:attrs

A list of attributes to return.

=back

=item groupAttr

The attribute in the member LDAP record that contains the group names.
    It is normally C<memberOF> in Window's ActiveDirectory.

=item regex

When LDAP returns a group, it returns the full I<Common Name> for that
group. Normally, you only want the first part of the name. For example,
the LDAP I<CN> might be:

    CN=AppTeam,OU=Groups,OU=Accounts,DC=mycorp,DC=com

but you want just the I<AppTeam> as the group name. You can use this
to pinpoint the group name in the expression. You use parentheses to
mark the place in the regular expression where you will find the
name of the group. For example, the following will pinpoint the
name of the group (I<AppTeam>) in the above expression:

	regex = ^[^=]+=([^,]+)

Note that the quoting slashes are not around the regular expression.
B<DO NOT INCLUDE THEM!>. Otherwise, your group anames will be messed up.

In fact, the above regular expression is pretty much the stanadard one
that you will use.

Note that the group name will be I<normalized> which means that it will
be uppercased and blanks will be replaced by underscores.

=back 

=head4 LDAP Example

Here's an example of what an LDAP section might look like. It pretty
much follows what someone who uses Windows Active Directory for
corporate access. 

	[ldap ldap://ldapserver.mycorp.com:389]
	bind = CN=subversion,OU=Users,OU=Accounts,DC=mycorp,DC=com
	bind:password = Sw0rdfi$h
	filter = sAMAccountName
	groupAttr = memberOf
	regex = ^CN=([^,]+),

=head1 AUTHOR

David Weintraub
L<mailto:david@weintraub.name>

=head1 COPYRIGHT

Copyright (c) 2010 by David Weintraub. All rights reserved. This
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
