READ ME - The most important file you've downloaded in Your Entire Life
===================================================

What's this?
------------

This what I call my *Kitchen Sink* Subversion pre-commit hook. When Subversion first came out, I was unhappy with the way *tags* were handled<sup>1</sup>. It was too easy to accidentally modify a tag and not have it caught.

There was already an access-control pre-commit hook that used Windows INI files, Perl regular expressions to match files, and the `read-only` and `read-write` access control. I rewrote that hook to include an `add-only` access control specifically for tags. Now, you can create, but not modify a tag.

Over the years, other features were added as requested by other users: Control properties, make comparisons to files case insensitive. Allow for the user of globs for matching file names, etc. I've also rewritten the hook several times as my Perl skills improved.

Now this hook can control several aspects of your repository:

1. **File Commit Permissions**: You can control who may or may not make changes to a file. This can be specified via a Perl regular expression (which gives you a lot of flexibility) or an [Ant style file globs](http://ant.apache.org/manual/dirtasks.html#patterns) (which are easier to understand). There are five separate permissions that can be set on files:
  * **`read-only`**: User cannot make changes to the file or directory.
  * **`read-write`**: User can commit changes to the file or directory.
  * **`add-only`**: User can add a directory via `svn cp`, but not modify any of the files in the directory. Perfect for tags.
  * **`no-add`**: User can modify and commit changes, and even delete the file or directory, but not add any new files or directories.
  * **`no-delete`**: User can modify and commit changes, but not delete the file.
1. **Require Properties on files**: You can require that particular files must have particular properties on them. For example, all files that end in `*.sh` or are in a directory called `bin` should have the `svn:executable` property. `Makefile` should have the property `svn:eol-tyle` set to `LF`, etc.
1. **Ban particular file names**: You may simply _ban_ file names. For example, Windows systems cannot have a file called 	`aux.*`, but this is allowed in Unix. If someone on a Mac or Linux system created  a file called `aux.java`, a user on a Windows machine would not be able to checkout or edit that project. Thus, you could ban users from adding any new files with a name that matches `**/aux.*`
1. **Require Revision Properties**: This is mainly for the `svn:log` revision property which is the _commit message_. You can make sure that this message is a minimum length, or require that all commit messages contain at least one issue id from your issue tracking system. However, other revision properties can now be specified during a commit, and many people have taken advantage of that to require specific revision properties like [`bugtraq:message`](http://tortoisesvn.net/docs/release/TortoiseSVN_en/tsvn-dug-bugtracker.html).
1. **LDAP/Windows Active Directory Integration**: This hook always allowed you to specify user groups on file commit permissions, but now you can use your LDAP/Windows Active Directory groups to help specify the groups you want to use when controlling file commit permission.

Printing out Documentation
--------------------------

* The Perl scripts use **POD** documentation (Plain Old Documentation) that's embedded in the scripts themselves. You can use the `perldoc` command (which should be in the same directory as your `perl` command) to print out the documentation:

    $ perldoc pre-commit-kitchen-sink-hook.pl
    
This will print out the document on your computer as text or manpage like documents.

You can use the `pod2html` command (also in the `perl` directory) to convert the document to *HTML* and then use a Web browser to print that out:

    $ pod2html pre-commit-kitchen-sink-hook.pl > pre-commit.html
    $ open -a Firefox pre-commit.html

The following are documented:

* **`new-pre-commit-hook` and `pre-commit-kitchen-sink-hook.pl`**: These contain the documentation on how to use the program including the various parameters.
* **Programming-doc directory**: This contains the documentation of al the _Perl classes used in the `new-pre-commit-hook`. This is in case you want to try making any changes yourself.
* **Control-file.md**: This is an explanation on how to create a control file and how it is structured.

The Two Pre-Commit Hooks
------------------------

There are two versions of this hook script. 

* `pre-commit-kitchen-sink-hook.pl`: This version is about five years old, and has been heavily patched, bug-fixed, and tested on hundreds of various sites. However, it is also deprecated.
* `new-pre-commit-hook.pl`: When I was a developer, I had a manager who said that any piece of code that's over five years old should be printed out, run through a shredder, burned, the ashes ground down to a fine powder, and then dispersed by the wind. After five years, the code is so heavily patched, it's unstable and you're afraid to touch it. Also, you've learned a lot, and new programming resources have come in that you can use. This version of my pre-commit hook is either the fifth or six complete rewrite.
	* The objects *defined* in the program are much cleaner which will make fixing issues or adding new features much easier to do.
	* I understand how LDAP works, and have improved its implementation.
	* I now use exception-based programming techniques which makes it easier to catch errors and to track down the errors.
	* The user error messages are cleaner and easier to understand. I now include a _policy_ message that explains the error and the description that is in the control file. I use dashed lines to help separate them, and boldly claim **COMMIT VIOLATION**. There's no mistake why you have the commit error any more.
	* If I find an error when parsing the control file, I show you the section, line, and the error. This makes it easier to fix control file errors.
	* One of the last features I added before the rewrite was the ability to put the control file inside the repository itself. However, if you made a mistake in the control file, you end up locking yourself out of the repository. I now parse the control file if you update it to make sure that the syntax is valid.
	
Therefore, I would prefer you to use the `new-pre-commit-hook.pl` I've ran it through a standard suite of tests I have created, and it should be ready for industrial usage. However, I know that there might be some bugs hidden deep inside, so I have the old hook that you can use as a backup.

However, that old hook has been deprecated. I will no longer be fixing bugs in that hook or adding new features. If you use the old hook and have a problem, I'll tell you to use the new hook.

Coding Style
------------

Perl has a reputation of being a _write only_ language. This is really an unfair allegation. Perl is an old and crufty language, and after 30 years, there are a lot of ..uh.. *features* that are no longer used. Plus, the fact that there are regular obfuscated  Perl coding contests doesn't help it's readability reputation.

One of the problems are regular expressions which are found in all languages, but Perl developers seem to really like. Regular expressions have been likened to sailor cussing in comic strips, but that's just the nature of regular expressions. They're pretty esoteric in almost any programming language.

Another is that Perl has some pretty flexible syntax. Some of that is probably a mistake - for example, Perl has a _default variable_ called `$_` that can be hidden from view. It was an attempt to make Perl more like a natural language, but really decreased legibility.

A lot of Perl programmers never learned Perl, and thus have hacked their way through it. Nor, do you need to use subroutines, variable scoping, or objects which make programs difficult to follow.

I do my best to make my code readable and easy to understand. I use a lot of objects and subroutines to help hide code complexity. I have a lot of comments and try to keep away from overly complex coding. Even Python developers have commented on how readable my code is.

The coding style is done to my very best, but feeble attempt to match
the coding style recommended by Damian Conway's [Perl Best
Practices](http://shop.oreilly.com/product/9780596001735.do). A book I
would highly recommend to all Perl developers. 

Reporting Bugs
--------------

I might not exactly be an illuminating light in the Perl developer
community, and you might find my coding attempts to be laughable.
However, one thing I am proud to be known for is handling bug reports.
My usual meantime to fix bugs or add a requested feature is usually
under 48 hours. If you give me enough information, I will usually have a
texted fix ready in a few hours.

If you find a bug **report it**. File a bug report on Github, and email
me at david@weintraub.name.

Copyright
---------

Copyright &copy; 2013 by the author, David Weintraub. All rights
reserved. This program is covered by the open source ***BMAB*** license.

The ***BMAB*** (Buy me a beer) license allows you to use all code for
whatever reason you want with these three caveats:

1. If you make any modifications in the code, please consider sending
   them to me, so I can put them into my code.
1. Give me attribution and credit on this program.
1. If you're in town, buy me a beer. Or, a cup of coffee which is what
   I'd prefer. Or, if you're feeling really spendthrify, you can buy me
   lunch. I promise to eat with my mouth closed and to use a napkin
   instead of my sleeves.
   
--
<sup>1.</sup> Making tags and branches full members of your version control system instead of mere meta-data actually has a lot of advantages. You get a complete history of when they were created, modified, and by whom and why. Plus, they're easily visible via `svn ls`. And, you can remove old tags without completely removing them. Thus they won't show up with an `svn ls`, but they're still in the repository.