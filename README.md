READ ME - The most important file you've downloaded
===================================================

What's this?
------------

This is what I call my Subversion *Kitchen Sink* hooks. The first
version of this was written back in 2002 when I first used Subversion. I
was shocked that it was so easy to modify a tag since tags were merely
branches. There was a pre-commit hook that allowed you to modify user
permissions by specifying parts of the repository with `read-write` and
`read-only` permissions using a Windows INI style control file.

I took the concept and added an `add-only` permission that allowed users
to create a tag, but not modify it. Later on, I started adding other
features I found useful, and started sharing this hook with others.

This pre-commit hooks can verify a commit in several different areas:

* **Files**: You may specify what files via a Perl style regular
  expression of via an Ant style glob expression, and then you can
  specify the permissions on those flies and who has these permissions.
  These permissions now include not only `read-write`, `read-only`, and
  `add-only`, but also `no-add` and `no-delete`.  .  Permissions are
  read from top to bottom, and the last matching permission to both the
  user and the file specification is used. Thus, one specification can
  take away the permission while another adds it back.
* **Ban**: Sometimes you simply need to keep things like spaces out of
  file names. The ban section allows you to specify file names that are
  banned either through Perl regular expression or Ant style globs. This
  only applies to newly added files.
* **Properties**: You can specify what properties are required on
  certain files via Perl regular expressions or Ant style globs. You can
  also specify the value of those properties via the exact property to
  match, or via a Perl regular expression.
* **Revision Properties**: You can specify required revision properties
  and their values. This is normally just done for the special Revision
  Property `svn:log` which is the Subversion commit message. This is
  usually done to require a commit message of a particular length, or to
  make sure that a bug or feature ID is embedded in the commit message.
  However, this can be used to require other revision properties too. A
  warning though: You must have Subversion version 1.5 or greater to be
  able to specify revision properties when you commit a change.
  Otherwise, you're stuck with just `svn:log`.

### Groups

This pre-commit hook uses groups to help set file permissions. You can
define a group in the `group` section header. Groups are read from top
to bottom, and groups can include other groups.

You can also use LDAP groups which is where the full power of this
function truly comes into play. 

### Control File

You configure this hook via a Windows style [INI
file](https://en.wikipedia.org/wiki/INI_file). The INI file format was
originally chosen because the hook I copied uses one. However, I've kept
the INI style because it is very easy to understand and use. Newer hooks
use JSON and XML, but these are simply too complex for this task at
hand.

There is a sample `control.ini` file for your perusal.

Printing out Documentation
--------------------------

The two Perl pre-commit hooks have self-contained documentation. You
should be able to use the C<perldoc> command to see this documentation:

    $ perldoc pre-commit-kitchen-sink-hook.pl

or

    $ perldoc new-pre-commit-hook.pl

This will print out all of the user documentation. The two programs will
also print out all of their documentation if you call them with the
`doc` command line parameter.

You can generate HTML documentation with the C<pod2html> command:

    $ pod2html new-pre-commit-hook.pl > new-pre-commit-hook.html

This can be opened up in a browser. Note that `perldoc` and the
`pod2html` commands are standard Perl commands that came with your
installation of Perl. They don't have to be downloaded or installed.
They are yours to use.

The Two Pre-Commit Hooks
------------------------

There are two versions of this hook script. The first is one I wrote
years ago and has been heavily tested.
(pre-commit-kitchen-sink-hook.pl). Unfortunately, it also shows that I
had a lot less programming experience. It includes poor object
definitions, and a rudimentary understanding on how LDAP works.

The new-pre-commit-hook.pl is a complete rewrite using better object
definitions, and a better LDAP setup. It is new and written from scratch
which means it is probably chock full of errors.

However, this is the new pre-commit hook that I am supporting. Errors
and bugs found will be fixed as quickly as possible, and feature
requests will be added. The older pre-commit-kitchen-sink-hook.pl is
being deprecated.

Class Documentation
-------------------

In the repository is a bunch of `*.pod` files. These are the files where
the classes used by the `new-pre-commit-hook.pl` are documented. You may
use the `perldoc` and the various `pod2xx` commands to see this
documentation.

Coding Style
------------

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

