REM precommit.bat script for Windows Systems

REM ### Set the location of the "svnlook" command below ###

set SVN_LOOK=C:\Program Files\CollabNet\Subversion Server\svnlook


set REPOS=%1
set TXN=%2
set HOOKS_DIR=%1\hooks

"%HOOKS_DIR%\pre-commit-kitchen-sink-hook.pl" -t %TXN% -svnlook "%SVN_LOOK%" -file "%HOOKS_DIR%\control.ini" "%REPOS%"
