require 'optparse'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'logger'
require 'stringio'
require 'shellwords'

Log = Logger.new(STDERR)

class IFTTX
  DEFAULT_FLDIGI_CMD = %w[xvfb-run --auto-servernum fldigi].freeze

  def run_fldigi options: {}, cmd: DEFAULT_FLDIGI_CMD, &block
    Dir.mktmpdir do |tmpdir|
      fldigi_dir = File.join(tmpdir, '.fldigi')
      fldigi_def = File.join(fldigi_dir, 'fldigi_def.xml')
      fldigi_prefs = File.join(fldigi_dir, 'fldigi.prefs')
      fldigi_talk = File.join(fldigi_dir, 'talk')
      fldigi_text = File.join(fldigi_talk, 'textout.txt')

      Log.debug {"fldigi: #{Shellwords.join(cmd)}"}
      options.each do |k, v|
        Log.debug {"Option: #{k}=#{v}"}
      end

      Log.info "fldigi home: #{tmpdir}"

      FileUtils.mkdir_p fldigi_talk
      FileUtils.touch fldigi_text

      options[:CONFIRMEXIT] = false
      options[:SAVECONFIG] = true
      options[:SPEAK] = true

      env = ENV.to_h
      env['HOME'] = tmpdir
      env['FLDIGI_CREATE_CONFIG_AND_EXIT'] = '1'

      Log.info "Initial start of fldigi"
      Open3.popen2e(env, *cmd, "--home-dir=#{tmpdir}") do |stdin, stdout_and_err, thread|
        if thread.value != 0
          raise RuntimeError, "fldigi exited with status #{thread.value}"
        end
      end

      Log.info "Rewriting configs (#{options.length} options)"
      rewritten_prefs = File.read(fldigi_prefs)
      options.each do |k, v|
        if !is_key?(k)
          raise ArgumentError, "invalid preference key #{k.inspect}"
        elsif !is_value?(v)
          raise ArgumentError, "invalid preference value #{v.inspect}"
        end

        rewritten_prefs.gsub! /^#{to_key(k)}:.*$/, "#{to_key(k)}:#{to_value(v)}"
      end
      File.write fldigi_prefs, rewritten_prefs

      # Need to do this by hand because fldigi's XML parser is bad.
      rewritten_def = File.read(fldigi_def)
      options.each do |k, v|
        if !is_key?(k)
          raise ArgumentError, "invalid default key #{k.inspect}"
        elsif !is_value?(v)
          raise ArgumentError, "invalid default value #{v.inspect}"
        end

        rewritten_def.gsub! %r[<#{to_key(k)}>[^<>]+</#{to_key(k)}>], "<#{to_key(k)}>#{to_value(v)}</#{to_key(k)}>"
      end
      File.write fldigi_def, rewritten_def

      Log.info "Relaunching fldigi"
      env.delete 'FLDIGI_CREATE_CONFIG_AND_EXIT'
      Open3.popen2e(env, *cmd, "--home-dir=#{tmpdir}") do |stdin, stdout_and_err, thread|
        File.open(fldigi_text, 'rb') do |text|
          begin
            tail fldigi_text, &block
          rescue
            return thread.value
          end
        end
      end
    end
  end

  private

  def is_key? key
    key.is_a?(String) || key.is_a?(Symbol)
  end

  def to_key key
    ret = key.to_s
    raise ArgumentError, "invalid key" if key =~ /[:<>]+/
    ret
  end

  def is_value? value
    value.is_a?(String) || value.is_a?(Symbol) || value.is_a?(Numeric) || !!value == value
  end

  def to_value value
    ret = ""
    if !!value == value
      # Boolean, special-case it.
      ret = value ? "1" : "0"
    else
      ret = value.to_s
    end
    raise ArgumentError, "invalid value" if ret =~ /[\n<>]+/
    ret
  end

  def tail filename, buffer_size=8, interval: 0.1
    File.open(filename, 'rb') do |file|
      file.seek(0, IO::SEEK_END)
      loop do
        new = file.read
        if new && !new.empty?
          yield new
        else
          sleep interval
        end
      end
    end
  end
end

options = {
  mode_name: :CW,
  squelch_enabled: false, sqlonoff: false, sqlevel: 0,
  int_pwr_squelch_level: 0, int_squelch_level: 0,
  MYNAME: 'IFTTX', MYCALL: 'IFTTX',
  CWTRACK: true, CWUSESOMDECODING: true,
  SQLCH_BY_MODE: false,
  AUDIOIO: 1,
}

regex = %r[PR ?(\d{6})]i
cmd = ['sh', '-c', 'echo "$*"']
fldigi = IFTTX::DEFAULT_FLDIGI_CMD

parser = OptionParser.new do |parser|
  parser.banner = "Usage: #$0 [options]"
  parser.on('-o', '--opt OPT',
            'Set an option in fldigi') do |val|
    key, _, value = val.partition('=')
    if value.empty?
      value = true
    end
    options[key] = value
  end
  parser.on('-r', '--regex REGEX',
            'Act on this regex') do |val|
    regex = Regexp.compile(val, Regexp::IGNORECASE)
  end
  parser.on('-c', '--cmd CMD',
            'Run this command with the parsed regex. $1, $2, etc are replaced with the match groups') do |val|
    cmd = Shellwords.split(val)
  end
  parser.on('-f', '--fldigi CMD',
            'Run this command as the fldigi command') do |val|
    fldigi = Shellwords.split(val)
  end
  parser.on('-h', '--help', 'Prints this help') do
    STDERR.puts parser
    exit
  end
  parser.separator ""
  parser.separator <<EOF
For example, to decode CW at frequency offset 1337, pass:
-o mode_name=CW -o wf_carrier=1337 -o CWSWEETSPOT=1337 \\
-o PORTINDEVICE='(name of input device)'

To match a Github PR, do something like:
-r 'PR ?(\\d{6})'

And if you want to run nixpkgs-review with the first match group, do:
-c 'sh -c "cd ~/projects/nix/nixpkgs && nixpkgs-review pr $1"'
EOF
end

parser.parse!

app = IFTTX.new

Log.info "IFTTX starting"
Log.info "If: #{regex.inspect}"
Log.info "Then: #{Shellwords.join(cmd)}"

str = StringIO.new
first = true
app.run_fldigi(options: options, cmd: fldigi) do |chunk|
  if first
    Log.info "Started to receive data via the logfile."
    first = false
  end
  chunk = chunk.gsub(/\s+/, '')
  str << chunk
  if !chunk.empty? && str.string =~ regex
    str.truncate(0)
    new_cmd = [*cmd, cmd.first, *$~.captures]
    Log.info "Got: #{$~[0]}"
    Log.info "Executing: #{Shellwords.join(new_cmd)}"
    Thread.fork do
      if !system(*new_cmd)
        Log.warn "#{Shellwords.join(new_cmd)} exited with status #$?"
      end
    end
  end
end
