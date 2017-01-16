#!/usr/bin/env ruby
# vim:et sw=2 ts=2

require 'fileutils'
require 'mkmf'
require 'digest/md5'
require 'timeout'
require 'taglib' 
require 'mediafile/version'

module MakeMakefile::Logging
  @logfile = File::NULL
end

class Numeric
  def to_duration
    [60,60,24].reduce([self.to_i]) do |m,o|
      m.unshift(m.shift.divmod(o)).flatten
    end
  end
end

module MediaFile

  autoload :MediaFile,      'mediafile/mediafile.rb'
  autoload :BulkMediaCopy,  'mediafile/bulkmediacopy.rb'

  missing = %i{ sox flac ffmpeg lame }.select do |cmd|
    !find_executable("#{cmd}")
  end
  if missing && missing.any?
    warn "The following executables weren't found in your $PATH: #{missing}\n" +
         "Transcoding may not work in all cases."
  end

  private

  @@thread_count = nil
  @@mutex = nil
  @@initialized = false

  def initialize_threads(count = 1)
    return if @@initialized
    @@initialized = 1
    @@thread_count = count
    if @@thread_count > 1
      require 'thread'
      @@mutex = Mutex.new
    end
  end

  def safe_print(message = '')
    lock {
      print block_given? ? yield : message + "\n"
    }
  end

  def cleanup
    @@mutex = nil
    true
  end

  def lock
    if @@mutex && !@@mutex.owned?
      @@mutex.synchronize do
        yield
      end
    else
      yield
    end
  end

  def debug(msg = '')
    safe_print("DEBUG: #{caller_locations(1, 2)[0].label} >> #{msg}") if @debug
  end

  def info(msg = '')
    safe_print("INFO: #{caller_locations(1, 2)[0].label} >> #{msg}") if @verbose
  end
end
