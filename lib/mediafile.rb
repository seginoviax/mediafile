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

  @@thread_count = 1
  @@semaphore = nil
  @@initialized = false

  def initialize_threads(count = 1)
    return if @@initialized
    @@initialized = 1
    @@thread_count = count
    if @@thread_count > 1
      require 'thread'
      @@semaphore = Mutex.new
    end
  end

  def safe_print(message = '')
    lock {
      print block_given? ? yield : message
    }
  end

  def cleanup
    @@semaphore = nil
    true
  end

  def lock
    if @@semaphore
      @@semaphore.synchronize {
        yield
      }
    else
      yield
    end
  end

 end
