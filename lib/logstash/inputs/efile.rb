# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"

require "pathname"
require "socket" # for Socket.gethostname
require "securerandom"

# Stream events from files.
#
# By default, each event is assumed to be one line. If you would like
# to join multiple log lines into one event, you'll want to use the
# multiline codec.
#
# Files are followed in a manner similar to `tail -0F`. File rotation
# is detected and handled by this input.
class LogStash::Inputs::Efile < LogStash::Inputs::Base
  config_name "efile"

  # TODO(sissel): This should switch to use the `line` codec by default
  # once file following
  default :codec, "plain"

  # The path(s) to the file(s) to use as an input.
  # You can use globs here, such as `/var/log/*.log`
  # Paths must be absolute and cannot be relative.
  #
  # You may also configure multiple paths. See an example
  # on the <<array,Logstash configuration page>>.
  config :path, :validate => :array, :required => true

  # Exclusions (matched against the filename, not full path). Globs
  # are valid here, too. For example, if you have
  # [source,ruby]
  #     path => "/var/log/*"
  #
  # You might want to exclude gzipped files:
  # [source,ruby]
  #     exclude => "*.gz"
  config :exclude, :validate => :array

  # How often (in seconds) we stat files to see if they have been modified.
  # Increasing this interval will decrease the number of system calls we make,
  # but increase the time to detect new log lines.
  config :stat_interval, :validate => :number, :default => 1

  # How often (in seconds) we expand globs to discover new files to watch.
  config :discover_interval, :validate => :number, :default => 15

  # Where to write the sincedb database (keeps track of the current
  # position of monitored log files). The default will write
  # sincedb files to some path matching `$HOME/.sincedb*`
  # config :sincedb_path, :validate => :string

  # How often (in seconds) to write a since database with the current position of
  # monitored log files.
  config :sincedb_write_interval, :validate => :number, :default => 15000

  # Choose where Logstash starts initially reading files: at the beginning or
  # at the end. The default behavior treats files like live streams and thus
  # starts at the end. If you have old data you want to import, set this
  # to 'beginning'
  #
  # This option only modifies "first contact" situations where a file is new
  # and not seen before. If a file has already been seen before, this option
  # has no effect.
  config :start_position, :validate => [ "beginning", "end"], :default => "end"

  # set the new line delimiter, defaults to "\n"
  config :delimiter, :validate => :string, :default => "\n"

  # set where the offsets are stored
  config :offset_path, :validate => :string, :default => ""

  public
  def register
    require "addressable/uri"
    require "filewatch/tail"
    require "digest/md5"
    require "metriks"
    require "thread_safe"
    require "fileutils"
    @logger.info("Registering file input", :path => @path)
    @host = Socket.gethostname.force_encoding(Encoding::UTF_8)

    @random_key_prefix = SecureRandom.hex
    @offsets = ThreadSafe::Cache.new { |h,k| h[k] = Metriks.counter(counter_key(k)) }
    if @offset_path != "" and File.exist?(@offset_path)
      deseralize_offsets
    end

    @tail_config = {
      :exclude => @exclude,
      :stat_interval => @stat_interval,
      :discover_interval => @discover_interval,
      :sincedb_write_interval => @sincedb_write_interval,
      :delimiter => @delimiter,
      :logger => @logger,
    }

    @path.each do |path|
      if Pathname.new(path).relative?
        raise ArgumentError.new("File paths must be absolute, relative path specified: #{path}")
      end
    end

    # if @sincedb_path.nil?
      if ENV["SINCEDB_DIR"].nil? && ENV["HOME"].nil?
        @logger.error("No SINCEDB_DIR or HOME environment variable set, I don't know where " \
                      "to keep track of the files I'm watching. Either set " \
                      "HOME or SINCEDB_DIR in your environment, or set sincedb_path in " \
                      "in your Logstash config for the file input with " \
                      "path '#{@path.inspect}'")
        raise # TODO(sissel): HOW DO I FAIL PROPERLY YO
      end

      #pick SINCEDB_DIR if available, otherwise use HOME
      # sincedb_dir = ENV["SINCEDB_DIR"] || ENV["HOME"]
      @tmp_dir = File.join(ENV["HOME"], ".efile_tmp_#{(rand*1000).to_i}/")
      sincedb_dir = Dir.mkdir(@tmp_dir)

      # Join by ',' to make it easy for folks to know their own sincedb
      # generated path (vs, say, inspecting the @path array)
      @sincedb_path = File.join(sincedb_dir, ".sincedb_" + Digest::MD5.hexdigest(@path.join(",")))

      # Migrate any old .sincedb to the new file (this is for version <=1.1.1 compatibility)
      # old_sincedb = File.join(sincedb_dir, ".sincedb")
      # if File.exists?(old_sincedb)
      #   @logger.info("Renaming old ~/.sincedb to new one", :old => old_sincedb,
      #               :new => @sincedb_path)
      #   File.rename(old_sincedb, @sincedb_path)
      # end

      @logger.info("No sincedb_path set, generating one based on the file path",
                   :sincedb_path => @sincedb_path, :path => @path)
    # end

    @tail_config[:sincedb_path] = @sincedb_path

    if @start_position == "beginning"
      @tail_config[:start_new_files_at] = :beginning
    end
  end # def register

  public
  def run(queue)
    @tail = FileWatch::Tail.new(@tail_config)
    @tail.logger = @logger
    @path.each { |path| @tail.tail(path) }
    @tail.subscribe do |path, line|
      @logger.debug? && @logger.debug("Received line", :path => path, :text => line)
      @codec.decode(line) do |event|
        event["[@metadata][path]"] = path
        event["host"] = @host if !event.include?("host")
        event["path"] = path if !event.include?("path")
        event["offset"] = @offsets[event['path'].to_s].count
        decorate(event)
        queue << event
        @offsets[event['path'].to_s].increment
      end
    end
    finished
  end # def run

  def counter_key(key)
    "#{@random_key_prefix}_#{key}"
  end # def metric_key

  public
  def teardown
    if @tail
      @tail.sincedb_write
      @tail.quit
      @tail = nil
      FileUtils.rm_r(@tmp_dir)
    end
    if @offset_path != ""
      seralize_offsets
    end
  end # def teardown

  private
  def seralize_offsets
    if File.exist?(@offset_path)
      File.delete(@offset_path)
    end
    open(@offset_path, 'a') do |f|
      @offsets.each_pair do |path, counter|
        f.puts "#{counter.count}:#{path}"
        @offsets.delete(path)
      end
    end
  end # seralize_offsets

  private 
  def deseralize_offsets
    open(@offset_path, 'r') do |f|
      f.each_line do |line|
        parsed_line = line.split(':', 2)
        count = parsed_line[0].to_i
        name = parsed_line[1]
        @offsets[name].clear
        count.downto(1) { |_| @offsets[name].increment }
        puts @offsets[name].count
      end
    end
    File.delete(@offset_path)
  end # deseralize_offsets

end # class LogStash::Inputs::File
