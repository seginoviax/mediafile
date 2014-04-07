#!/usr/bin/env ruby
# vim:et sw=2 ts=2

require 'fileutils'
require 'digest/md5'
require 'timeout'
require 'taglib' 
require 'mediafile/version'

module MediaFile

  autoload :MediaFile,      'mediafile/mediafile.rb'
  autoload :BulkMediaCopy,  'mediafile/bulkmediacopy.rb'

end
