The program e is a command line is a simple utility to extract different archives.
it may work perfectly out of the box for you.  Otherwise you can configure rules for any kind of file.

== Extraction Rules
It is inspired by how firewall use their rulesets, and works like this:
 
* For each file that has to be extracted, the rules are matched one after the other.
* If a rule matches, the extraction command is executed, and the next file will be processed.
* If the rule does not match the next rule will be tried.

Each rule consists of 1 or 2 patterns and the command to be executed if a pattern is matched.
In the command to execute, #{f} is replaced by the filename.

There are two types of patterns:
 1. filetype: a pattern that does not begin with a '.'
   This patter is matched against the output of the "file -b" command.
 2. filename: a pattern beggining with a '.'
   This is a file extension pattern that will be matched against the end of the filename

A match attempt will first be made against all fileype patterns, then the filename patterns will be evalueated.  matches will be attempted in the order they appear in the rule list.

All patterns will be converted to regular expressions without escaping metacharacters with the following exception: A filename match has '.' escaped and is wrapped in ( )$ to match the end of the filename
