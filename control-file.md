Control File Layout
===================

This program uses what is known as an [Windows INI
style](https://en.wikipedia.org/wiki/INI_file) control file to
control the pre-commit hook. I chose this because this type of file
layout is easy to understand and simple to maintain.

What is an Windows Ini File?
---------------------------

A Windows Ini file consists of sections marked by a section header.
Under each section header is a series of parameters for that header.
Section headers have square brackets around them, and parameter consists
of a line that has a parameter name, followed by an equal sign followed
by the value of that parameter. Here is a simple example:

    ; This is some made up section

    [Section1]
    param1 = value1
    param2 = value2
    param3 = value3

    # This section is a bit more real

    [Configuration]
    backup = C:\backupdir
    extention = ini
    param3 = another value

Ini files can also contain comments. Comments are lines that begin with
a semicolon (or sometimes a pound-sign). 

The above Ini file has two sections, and each section has three
parameters. Note that both sections have a parameter called `param3`.
This is fine. Parameters can be duplicated between sections, but you
cannot have the same parameter inside a single section. This file also
contains two comments.

Pretty simple? That is why I use the INI format. It has limited
flexibility since there is only two levels, but that is more than good
enough for my use.

There is one bit of complexity I do: Section headers actually consist of
two parts. The first word in a section header is the *type* of section
it is. The rest of the section header is a description for that section.
This description is used as part of the error message.

    [file Only someone from the CM team is allowed to modify build.xml files]
    file = **/build.xml
    access = read-write
    users = @cm

In the above example, this *section type* is a *File*. The rest is a
description of that section. Unlike regular Windows INI files, you can
have identical section titles:

    [file Only someone from the CM team is allowed to modify build.xml files.]
    file = **/build.xml
    access = read-only
    users = @all

    [file Only someone from the CM team is allowed to modify build.xml files.]
    file = **/build.xml
    access = read-write
    users = @cm

The above example has two sections and both have identical descriptions.
Both are of a type *File* which means I am controlling the permission on
who can make changes to the `build.xml` files. In the first one, I take
away the permission for anyone to make changes to any `build.xml`. In
the second section, I allow users of the `@cm` group to make changes.

If someone who does not have permission to make changes to the `build.xml` file tries to change the file, they'll get this error:

    COMMIT VIOLATION: In "/trunk/prog/build.xml"
    	Only someone from the CM team is allowed to modify build.xml files.
		You don't have access to change "/trunk/prog/build.xml"
		
Note how the second line in the error message is from the Section's description.

Sections are read from top down. For example, you can define groups, and groups can contain other groups. However, are defined from the top down. *Group B* can contain *Group A* only if you've defined *Group A* before *Group B*.

Section types
-------------

Sections all have types (as explained above). In the sample control file, they are all grouped together. This isn't necessary, but does make maintaining your control file easier to do.

###File

File sections are the heart of this hook. They allow you to define who has permission to make changes to what files. 

Permissions are read from the top down, and the last file section that applies is the permission granted. This means you can take away permission with one file section, allow it in another, and then take it away again in the third.


There are several parameters used by a **File** section. Section parameters are case insensitive.


* **file**: Use Ant file globs to define the files with this permission. Ant globs are always anchored to the front and back, so if you simply specify `**.java`, it probably won't match anything in your repository. You need to specify `**/*.java`. File parameters are converted into regular expressions. You should not use the `file` parameter and the `match` parameter together. The string `<USER>` will be replaced by the ID of the user who made the commit. This id will be converted to all lowercase and white spaces will become underscores.
* **match**: Use Perl regular expressions to match the file's name. This is more powerful than Ant globs, but are also trickier to get right. Unlike globs, regular expressions are not anchored unless you specify that. The string `<USER>` will be replaced by the ID of the user who made the commit. The string `<USER>` will be replaced by the ID of the user who made the commit. This id will be converted to all lowercase and white spaces will become underscores.
* **users**: A list of users or groups this section applies to. User names may be either separated by whitespace or commas. There's a special group `@all` that applies to all users. Group names begin with an at-sign.
* **case**: Optional parameter. Whether case is significant when matching the file's name. The two valid values are `match` and `ignore`. The default is `match`. The case of the value of this parameter is not significant. 
* **access**: The access the committer has with this file. Case is not significant with this parameter's value. The valid access types are:

	* **read-only**: Committer has no permission to change this file.
	* **read-write**: Committer has complete permission to change, add, or delete this file.
	* **add-only**: A special permission to allow the committer to use `svn copy` to copy a directory from one part of the repository to another, but not to edit or delete the directories or files. This is used to allow users to create tags, but not make a change in the tag once it is created.
	* **no-add**: Committer may make changes or delete the file, but not to add a new file to the repository.
	* **no-delete**: Committer can create a new file or modify an existing one, but is not allowed to add a new file to the repository.
	
####Examples

	[file Users may only create a tag, but not modify the tag.]
	file = /tags/**
	access = read-only
	users = @all
	
	[file Users may only create a tag, but not modify the tag.]
	file = /tags/*/
	access = add-only
	users = @all
	
	[file Configuration managers may modify tags]
	file = /tags/*/
	access = read-write
	users = @cm bob
	
This example is setting up permissions to allow all users to create a tag, but not to be allowed to edit a tag. The first section removes the ability to make any changes under the `/tags/**` directory at all. The section section allows all users to have `add-only` access to tags. The last section allows all users in the `@cm` group to make modifications in tags, and it also allows user with the ID of `bob` to do the same.

If a user tried to modify a tag, the error message will be taken from the first description _Users may only create a tag, but not modify the tag_.

	[file Users may only edit their own Watch files.]
	file = /watcher/**
	access = read-only
	users = @all
	
	[file Users may only edit their own Watch file.]
	file = /watcher/<USER>.cfg
	access = read-write
	users = @all
	
The first section is taking away anyone's permission to modify any file under the `/watcher` sub-directory. The second enables all users to edit only their own watch file. For user David, the `<USER>` string is replaced by `david`:

	[file Users may only edit their own Watch file.]
	file = /watcher/david.cfg
	access = read-write
	users = @all
	
For user _Bob_, it is replaced by `bob`:

	[file Users may only edit their own Watch file.]
	file = /watcher/bob.cfg
	access = read-write
	users = @all

Note that this happens only in `match` and `file` sections. This will not work:

	[file Users may only edit their own Watch file.]
	file = /watcher/<USER>
	access = read-write
	users = <USER>
	
This will apply only to a user named `<USER>`.

###Group

As hinted above, you may define groups. Groups do not have to be defined before a file section that uses them. However, if you define one group based upon another, that *contained* group must be defined before the second group may use it.

In groups, the section description is the group's name. Groups only have a single parameter, *users* which contains a list of users and groups that are members of the group. Like the *users* parameter in *File* sections, the groups and user names can be white space separated, comma delimited, or both.

####Examples

	[group admins]
	users = peter paul mary
	
	[group developers]
	users = bob carol ted alice @admins
	
	[group managers]
	users = tom dick harry @executives
	
	[group executives]
	users = winky blinky nod
	
In the above examples, the group `admins` contains three users. The group `developers` contains four users plus the users in `admin`. However, the group `managers` only contains three users since the `executives` group is not defined when `managers` is created.

###Ldap

Many places use Windows Active Directory or LDAP servers as a way of providing Subversion access. LDAP servers can also be used to provide group definitions for this hook. 

Under LDAP users names and groups are *normalized* by being lowercased and white spaces are replaced with underscores. Thus if the LDAP user is named  *Bobby Roberts*, in this hook, the user name will be *bobby_roberts*.

Ldap group names are also normalized in the same way. *IT Development Security Group* becomes *it_development_security_group*. LDAP groups are also processed before the various *Group* sections -- even if they are defined later in the control file. This means that you can use LDAP groups in *Group* sections. Some people use this to provide an alias for the LDAP group:

	[group it]
	users = @it_development_ldap_security_group
	
The above aliases the *IT Development LDAP Security Group* group to just *it* which makes it easier to use in *File* sections:

	[file Allow IT department access to server configuration files]
	file = /trunk/config/servers/**
	access = read-write
	users @it
	
There is usually a single LDAP although the control file can handle multiple groups. The Section name of the LDAP group will start with the word `ldap` and the _description_ is the full URL for that LDAP server, including whether it's LDAP or LDAPS, and the port used. Some sites have multiple LDAP servers including ones used for backups. You may specify them all in the Section header.

An LDAP section may take several parameters:

* **base** (required): This is the LDAP base DN, usually just the DC part.
* **user_dn** (optional): This is the dn of the user that is connecting to the LDAP server. If not given, the *binding* to the LDAP server will be done anonymously. Almost all of the sites will require a user DN to connect to the LDAP server. It is highly recommended that the user DN used here should have no other permissions except to read and search the LDAP tree since this user's password is exposed on the Subversion server. ***Hint***: This should be the same user is used in the Subversion Apache httpd configuration too.
* **password** (optional): This is the password for the above user needed to access the LDAP tree. If the password is not given, the **user_dn** will be used without a password.
* **search_base** (optional): This is the LDAP sub-tree to start your searching on. If not given, searches will be from the **base** fo the LDAP tree. Most of the time, this doesn't really make much difference if the LDAP tree is well indexed. However, it can speed up searches in sites with bad or nonexistent indexing.
* **username_attr** (optional): The attribute that should match the user's Subversion name. By default, this will be `sAMAccountName`. This must be the same attribute used in the Subversion Apache httpd configuration.
* **group_attr** (optional): The name of the attribute that contains the names of the groups that the user is in. By default, this will be `memberOf`.
* **Timeout** (optional): This is the LDAP server timeout. It is five seconds by default. If the hook cannot contact and *bind* to the LDAP server within the _timeout_, the pre-commit hook will fail. This should be more than enough time. However, some sites need a longer timeout.

####Examples:

	[ldap ldap://ldap.vegicorp.com:389 ldap://ldap2.vegicorp.com:389]
	base = dc=vegicorp,dc=com
	
The above configuration contains a primary and backup LDAP server. The only parameter defined is **base**. This will bind anonymously the LDAP server. Match the user against the `sAMAccountName` LDAP attribute, and use the LDAP attribute `memberOf` to get the required groups.

	[ldap ldap://ldap.vegicorp.com:389 ldap://ldap2.vegicorp.com:389]
	base = dc=vegicorp,dc=com
	user_dn = cn=The CM Guy,ou=California,ou=Users,dc=vegicorp,dc=com
	password = swordfish
	username_attr = mail
	group_attr = memberOf
	
In this case, the user LDAP user `The CM Guy` with a password of `swordfish` is used to *bind* to one of the LDAP servers. At this site, users apparently log into Subversion using their email address. However, the default LDAP attribute with the group names is still `memberOf`.

###Ban

The *Ban* sections are used to specify file names that are simply not allowed. This will override the *File* section, and only applies to newly added files. Users will still be allowed to commit changes to files that have a _banned name_ if that file is already in the repository.

The *Ban* section consists of the word `ban` and a policy description that will be used as en error description.

The *Ban* section can take one of two parameters:

* **match**: This is a regular expression defining the name of the banned file.
* **file**: This is a Ant file glob defining the name of the banned file.

Only one or the other should be used.

####Example:

	[ban Illegal Windows Filenames are Not Allowed.]
	match = /(con|aux|prn|com[1-4])\.?
	
These would be names such as `con.bat` or `prn.cc` or `com1.sh` which are all illegal under Windows.

	[ban Filenames Cannot Contain Chars That Cause Problems in Subversion]
	file = **/*@*/**
	
This will prevent any file that contains an at-sign in its name.

	[ban No spaces in file names]
	match = \s
	
Spaces are not allowed in file names.

###Property

Property sections allow you to define what files must have particular properties and what values those properties have to be. There are usually three cases of concern here:

1. **Files that are specific to a particular OS need that OS's line ending:** In Unix and Unix like operating systems, shell scripts, Makefiles, and a few other file types require a end of line with just the `LF` character on it. Windows Batch files, VisualStudio project files, and other *Windows only* files must have a `CR` followed by a `LF` character.
1. **Files that are executable should be executable when checked out of Subversion**. This may mean shell scripts, Perl scripts, Python scripts, and even executables. Usually, this can be done by suffix or by the name of the directory where the files are located (like `bin`).
1. **Non-binary files should be marked as such**: The big problem here are PDF files that Subversion may believe are text files. Thus, Subversion will attempt to do merges on them.

Some sites use `bugtracq` properties on folders for [TortoiseSVN](http://tortoisesvn.net) use. 

The *Property* section starts with the word `property` and contains a description that will be used for error messages. The *Property* section has the following parameters:

* **file**: Use Ant file globs to define the files with this permission. Ant globs are always anchored to the front and back, so if you simply specify **.java, it probably won't match anything in your repository. You need to specify **/*.java. File parameters are converted into regular expressions. You should not use the file parameter and the match parameter together.
* **match**: Use Perl regular expressions to match the file's name. This is more powerful than Ant globs, but are also trickier to get right. Unlike globs, regular expressions are not anchored unless you specify that. The string <USER> will be replaced by the ID of the user who made the commit.
* **property**: The name of the property that needs to be set.
* **value**: The value of that property. If the property is set, and is not equal to this value, the commit will still be rejected. This can be a regular expression that needs to be matched. You can use this to give your property value a bit of flexibility.
* **type**: The type of property value expected. This can be `number`, `string` or `regex`. If the type is `number`,  `1.00` and `1` will both match, but won't match if the type is `string`.
* **case: Optional parameter. Whether case is significant when matching the file's name. The two valid values are `match` and `ignore`. The default is `match`. The case of the value of this parameter is not significant.

***NOTE***: That *match* is for the file name and not the property's value.

####Examples

	[property Shell scripts require the property "svn:eol-style" to be set to "LF"]
	file = **/*.k?sh
	property = svn:eol-style
	value = LF
	type = string

	[property Scripts require property "svn:eol-style" to be set to "native"]
	match = \.(pl|pm|py)$
	property = svn:eol-style
	value = native
	type = string

	[property Executable scripts require property "svn:executable" on them]
	match = \.(sh|ksh|pl|pm|py)$
	property = svn:executable
	value = .*
	type = regex


###Revprop

Revision Properties are very much like properties, but apply to the revision and not to files. There are three main revision properties:

1. **svn:log**: This is the commit message
1. **svn:author**: This is the committer
1. **svn:date**: This is the date of the commit.

Of these, only `svn:log` is usually checked because that's the one the committer may control.

Other revision properties, since Subversion 1.5 can be set by the `--revprop` parameter on `svn commit`.

The *Revprop* section starts with the word `revprop` and contains a description that will be used for error messages. The *Property* section has the following parameters:

* **property**: The name of the revision property that needs to be set.
* **value**: The value of that property. If the property is set, and is not equal to this value, the commit will still be rejected. This can be a regular expression that needs to be matched. You can use this to give your property value a bit of flexibility.
* **type**: The type of property value expected. This can be `number`, `string` or `regex`. If the type is `number`,  `1.00` and `1` will both match, but won't match if the type is `string`.

####Example:

	[revprop Jira issue IDs must be prefixed to commit comment followed by ":"]
	property = svn:log
	value = ^((NONE)|([A-Z]{3.4}-[0-9]+,?)+):\s+.{10,}
	type = regex

In the above case, the commit message must start with a Jira issue ID or the word `NONE` followed by a colon and then at least a ten character commit comment. Users can specify multiple Jira IDs with comma separations.

Processing
----------

All Control files are processed in batch in the order they are on the command line, but the ones in the file system are read in first. The entire contents of all control files are read in, and each Section type is loaded in the order it is read. However, section types are processed in the following order:

* Ldap Sections
* Group Sections
* File, Ban, and Properties all together
* Revision Properties after all other files are processed.

This means that Group sections can depend upon the Ldap groups being processed even if the Ldap Sections are after that Group section. It means that file Sections can depend upon groups being processes even if those groups are defined after that File section.

There is no need to have all the same group together in your control file although doing so makes it easier to maintain.

Putting the control file inside your repository makes it easier to maintain since you do not need server access in order to maintain it. However, it is highly recommended that the control file containing the LDAP section be kept as a system file on your Subversion server, and the permissions set, so only the user executing the Subversion server process may read it since the Ldap section contains the Ldap password.

Another advantage is that you can allow other users to edit control files. For example, you may want project managers to be able to edit the control file that covers their project, so they can say who may or may not edit a particular set of files.

Care must be taken that the control file is valid. When a control file in the Subversion repository is edited, it is parsed to make sure it is a valid control file. However, it is still possible for a user to edit the control file in such a way, no one may commit any changes. In that case, you need to turn off the pre-commit hook, and back out the control file changes.

What keeps unauthorized users from changing the control file itself? Simple, the control file contains rules to prevent unauthorized users from accessing the control file.