
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
require 'mediafile/version'

Gem::Specification.new do |s|
  s.name        = 'mediafile'
  s.version     = MediaFile::VERSION
  s.date        = Time.now.strftime('%Y-%m-%d')
  s.summary     = 'Parse media file metadata.'
  s.description = 'Parse media file metadata, copy or transcode mediafiles.'
  s.authors     = ['Jeff Harvey-Smith']
  s.email       = ['jharveysmith@gmail.com']

  s.required_ruby_version = '~> 2'

  s.add_dependency 'taglib-ruby', '~> 0.6', '>= 0.6.0'


  s.files       = Dir["./lib/**/**"] + Dir["./bin/*"]
  s.executables << 'music_cp'
  s.homepage    = 'https://github.com/seginoviax/mediafile'
  s.licenses    = ['MIT']
end
