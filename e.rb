#!/usr/bin/env ruby
# License:: public domain

alias fn lambda

###
#################### begin user configuration ####################
###
# filetype, file-extension, extraction command
$rules = [
[ '(^Zip archive)|( ZIP )', '.zip|.ZIP', fn{|f| "unzip #{f}"} ],
#['^RPM', fn{|f| "rpm2cpio < #{f} | cpio -i -d --verbose"} ],
[ '^RPM',                     fn{|f| "alien -k #{f}"} ],
#[ '^7-zip',          '.7zip', fn{|f| "7z x #{f}"} ],
#[ '^7-zip',         '.7zip', fn{|f| "7zr x #{f}"} ],
[ '^7-zip',         '.7zip', fn{|f| "7za x #{f}"} ],
[ 'tar archive',     '.tar',  fn{|f| "tar -xvf #{f}"} ],
[ '^RAR archive',    '.rar',  fn{|f| "unrar -x -o+ #{f}"} ],
#[ '^RAR archive',            fn{|f| "rar -e #{f}"} ],
#[ '^Debian.*package',        fn{|f| "dpkg -x #{f} ."} ],
#[ '^Debian.*package',        fn{|f| "ar -x #{f}" ],
[ '^Debian.*package',         fn{|f| "sudo dpkg --install #{f}"} ],
[ ' ar archive',              fn{|f| "ar -xv #{f}"} ],
[ '^LHarc ',                  fn{|f| "lha -x #{f}"} ],
[ '^ARJ ',                    fn{|f| "arj -x #{f}"} ],
[ 'MS CAB-Installer', '.cab', fn{|f| "cabextract #{f}"} ],
[ '^ACE ',                    fn{|f| "unace -e #{f}"} ],
[ '^PPMD archive',            fn{|f| "ppmd -d #{f}"} ],
[ '.tar.lzma|.tlz',           fn{|f| [:system, "lzma -d -si -so < #{f} |tar -xv"]} ],
[ '.rz',                      fn{|f| "rzip -d -k -v #{f}"} ],
[ '.dar',                     fn{|f| "dar -v -x #{f}"} ],
[ '.uha',                     fn{|f| "wine uharc x #{f}"} ],
[ 'ZZip archive',             fn{|f| "zzip x #{f}"} ],
[ 'Zoo archive',              fn{|f| "zoo -extract #{f}"} ],

# recognize tarred archives
[ '^lzop ', '.lzo|.lzop|.zo', fn {|f|
  if f =~ /(?:\.tar\.lzo|\.tzo|\.tar\.lzop)$/ then [:system, "lzop -c -d #{f} | tar -xv"]
  else                                             "lzop -x -f #{f}"
  end }
],
[ 'bzip2 ', '.bz2', fn {|f|
  if f =~ /(?:\.tar\.bz2|\.tbz)$/ then "tar -xjvf #{f}"
  else                                 "bzip2 -dk #{f}"
  end }
  ],
# gzip by default removes the file, must use -c inputFile > outputFile
[ 'gzip ', '.gz', fn {|f|
  if f =~ /(?:\.tar\.gz|\.tgz)$/ then "tar -xzvf #{f}"
  else [:system, "gunzip -c #{f} > #{f.dup.sub!(/\.gz$/, '') || (f + '.unzipped')}"]
  end }
]
]

###
#################### END USER CONFIGURATIONS ################
###

# make every rule have the same format (let user be flexible) :
#   filetype pattern, filename pattern, command
# insert nil in place of nonexistent patterns
$rules.map! do |r|
  case r.size
  when 3
    r[1], r[0] = r[0], r[1] if r[0][0,1] == '.'
  when 2
    if r[0][0,1] == '.' then r.unshift( nil ) else r.insert( 1, nil ) end
  else
    fail "invalid rule:\n#{r}"
  end
  # prepare for transform to a regular expression
  r[1] = '(?:' << r[1].gsub('.', '\.') << ')$' if r[1]
  r
end

################### BEGIN PARSE COMMAND LINE ###############
def help; <<-EOS
  usage: e archive [ archive2 archive3 ... ]
          --help        show this message
          --exts        list matched file extensions
          --types       list matched file types
          --rules       list matched file types
          -             accept piped input
EOS
end

def exit_msg msg, code=1
  puts msg; exit(code)
end
exit_msg( help(), 0 ) if ARGV.empty? 

def re_to_text( regexes )
  regexes.compact.map do |str|
    str.gsub('\.', '.').gsub('(?:','').gsub('(','').gsub(')','').split('|')
  end
end

def check_files(files)
  files.each do |file|
    if !(File.exist?( file ))
      exit_msg(*
      case file
      # accept piped input
      when '-'
        return check_files( $stdin.readlines.map {|line| line.chomp } )

      # s on the end is optional
      when /^--type/  then [re_to_text( $rules.map {|r| r[0]} ), 0]
      when /^--ext/   then [re_to_text( $rules.map {|r| r[1][3..-3] if r[1]} ), 0]
      when /^--help/  then [help(), 0]
      when /^--rule/  
        formats = [0,0,0]
        $rules.map! do |rule|
          rule[0] ||= ""; rule[1] ||= ""
          rule[2] = [*(rule[2].call "FILE")].join(' ')
          rule.each_with_index do |s,i|
            formats[i] = s.length if (s.length) > formats[i]
          end
        end.map! {|r| sprintf "%#{formats[0]}s|%#{formats[1]}s|%#{formats[2]}s", *r}
        [$rules, 0]
      when /^--?\w*$/ then [help(), 1]
      else                 ["archive does not exist: #{file}", 1]
      end)
    end
  end
  files
end
files = check_files(ARGV)
################### END PARSE COMMAND LINE ###############

require 'fileutils'

class ExtractionError < Exception; end
class SystemExtractionError < ExtractionError; end

# return nil if no change made to filename
class File; def File.make_unique!( file )
  if File.exist? file
    file << '+' << Time.now.to_i.to_s while File.exist? file
    return file
  end
end end

# move contents out of the current temp directory back to original directory
# ensure there is a base directory and that its name does not have conflicts
def mv_no_pollute( unpolluting_name="extracted", dest='..' )
  msg =
  case (entries=Dir.entries('.').reject{|e| e == '.' || e == '..'}).size

  when 0
    unless File.exist? unpolluting_name.sub(/\.[^.]$/,'')
      raise ExtractionError, "no files extracted"
    end
  when 1
    # check if there is a file/directory with the same name
    if File.make_unique!( new_dest = (dest + '/' + entries[0]) )
      Dir.mkdir new_dest
      dest = new_dest
      "directory with same name"
    end

  # prevent polution by creating a new directory to place these files in
  else
    dest << '/' << File.basename( unpolluting_name ).sub(/\.[^.]*$/, '')
    new_name = File.make_unique! dest
    Dir.mkdir dest
    "creating directory to place files in" if new_name
  end

  puts "#{msg}, inflating to: #{File.expand_path(dest)}" if msg

  FileUtils.mv(entries, dest)
end

# this is like backticks, but the command will be shell escaped
def run command, filename
  # split command on whitespace. But remove the file- it could have whitespace
  # this means all commands should not have whitespace- this should hold
  splitup = []
  i = -1
  while maybei = (slice = command[i + 1 .. -1]).index(filename)
    i = maybei
    splitup.push command[0...i].split(/\s+/).push(filename)
    i += filename.length
    break if i == command.length
    fail if i > command.length
  end

  splitup.push slice.split(/\s+/) if i < command.length
  c = splitup.flatten.compact

  res = nil
  IO.popen('-') {|io| io ? io.read : res = exec(c.shift, *c)}
  return <<-EOS if $?.exitstatus != 0

exit code: #{$?.exitstatus}
command result:
#{res}

failure on command:
#{c.join(' ')}
EOS

  res
end

def match_and_extract( filename, matcher, rule_set )
  rule_set.find { |regex, command_proc|
    if( matcher.match( regex ) )
      runner = :run
      command = command_proc.call( filename )
      runner, command = command if Array === command

      res = if method(runner).arity == 2
        send(runner, command, filename)
      else
        send(runner, command)
      end

      if $?.exitstatus == 0
        mv_no_pollute( filename ) || true # stop the find command for sure
      else
        raise SystemExtractionError, res
      end
    end
  } || yield # find command exhausted, caller should deal with it
end

def extract_file( file, type_rules, name_rules )
  match_and_extract( file, `file -b '#{file}'`.chomp, type_rules ) do
    # filetype not found, try filename
    match_and_extract( file, file.sub(/^[^.]+/,''), name_rules ) do
      raise ExtractionError, "no rules found to extract: #{file.sub('../','')}"
    end
  end
end

# make sure the archive has a root directory and
# does not dump a bunch of files out when extracted
# extract to the temporary directory first
$tmpdir='./tmp'
def make_temp_dir
  File.make_unique!( $tmpdir )
  Dir.mkdir( $tmpdir ); Dir.chdir $tmpdir
end
def remove_temp_dir
  Dir.chdir '..'
  begin
    Dir.rmdir( $tmpdir )
  rescue SystemCallError # directory not empty (most likely due to interruption)
    raise ExtractionError, "\nproblems occurred.. partial extraction to #{$tmpdir}"
  end
end

type_rules = $rules.map {|type, name, command|
  [Regexp.compile(type), command] if type }.compact
name_rules = $rules.map {|type, name, command|
  [Regexp.compile(name), command] if name }.compact

errors = []
make_temp_dir()
at_exit do
  remove_temp_dir() rescue puts($!.to_s)
  unless errors.empty?
    puts("\nERROR: unsuccessful extractions:\n\n" <<
    errors.map do |fileName, error|
      "#{fileName}\n  ERROR:    #{error}\n  filetype: #{`file -b '#{fileName}'`}"
    end.join("\n") )
    exit!(1)
  end
end

files.each_with_index do |file, i|
  # currently in ./tmp directory
  relative_file = (file[0,1] == '/') ? file : ("../" + file) 
  begin
    extract_file( relative_file, type_rules, name_rules )
  rescue ExtractionError => e
    if e.class == SystemExtractionError
      remove_temp_dir rescue nil
      make_temp_dir
    end
    errors.push [file, $!.to_s.dup]
  end
end
