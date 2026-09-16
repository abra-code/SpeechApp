-- speech.trash.applescript - move one file to the Trash through Finder, so the user finds it where
-- a Mac user looks for a file they did not mean to lose, and Put Back still works.
--
-- The path arrives as an argument rather than in the text of the script, so nothing in a recording's
-- name can be read as AppleScript. A file that is not there, or that Finder may not touch, raises an
-- error, which osascript reports on stderr with a non-zero status: the caller shows it.

on run argv
	if (count of argv) is less than 1 then error "speech.trash: no file to move" number -1700
	set thePath to item 1 of argv
	tell application "Finder" to delete (POSIX file thePath as alias)
end run
