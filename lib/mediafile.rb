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

end
