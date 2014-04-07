
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
require 'mediafile/version'

Gem::Specification.new do |s|
  s.name        = 'mediafile'
  s.version     = MediaFile::VERSION
  s.date        = '2014-02-27'
  s.summary     = 'Parse media file metadata.'
  s.description = 'Parse media file metadata, copy and/or transcode mediafiles.'
  s.authors     = ['Jeff Harvey-Smith']
  s.email       = ['jharveysmith@gmail.com']

  s.required_ruby_version = '~> 2'

  s.add_dependency 'taglib-ruby', '~> 0.6.0'


  # The following block of code determines the files that should be included
  # in the gem. It does this by reading all the files in the directory where
  # this gemspec is, and parsing out the ignored files from the gitignore.
  # Note that the entire gitignore(5) syntax is not supported, specifically
  # the "!" syntax, but it should mostly work correctly.
  root_path      = File.dirname(__FILE__)
  all_files      = Dir.chdir(root_path) { Dir.glob("**/{*,.*}") }
  all_files.reject! { |file| [".", ".."].include?(File.basename(file)) }
  all_files.reject! { |file| file.start_with?("website/") }
  gitignore_path = File.join(root_path, ".gitignore")
  gitignore      = File.readlines(gitignore_path)
  gitignore.map!    { |line| line.chomp.strip }
  gitignore.reject! { |line| line.empty? || line =~ /^(#|!)/ }
  unignored_files = all_files.reject do |file|
    # Ignore any directories, the gemspec only cares about files
    next true if File.directory?(file)

    # Ignore any paths that match anything in the gitignore. We do
    # two tests here:
    #
    #   - First, test to see if the entire path matches the gitignore.
    #   - Second, match if the basename does, this makes it so that things
    #     like '.DS_Store' will match sub-directories too (same behavior
    #     as git).
    #
    gitignore.any? do |ignore|
      File.fnmatch(ignore, file, File::FNM_PATHNAME) ||
        File.fnmatch(ignore, File.basename(file), File::FNM_PATHNAME)
    end
  end
  s.files       = unignored_files
  s.homepage    =
    'http://rubygems.org/gems/mediafile'
  s.licenses    = ['MIT']
end
