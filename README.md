mediafile
=========

mediafile ruby gem and music_cp program

Usage: music_cp [options]
    -f, --file FILE|DIR              File or directory to copy.
                                     If given a directory, will grab all fileswithin non-recursively
    -r, --recursive DIR              Directory to recursively scan and copy
    -d, --destination PATH           Where to copy file to. Default: '.'
                                     Will be created if it doesn't exist.
        --transcode <from=to[,from1=to1]>
                                     A comma-seperated list of name=value pairs.
                                     Default is flac=mp3,wav=mp3}
    -c, --copy                       Turn off transcoding.
        --[no-]progress              Set show progress true/false.  Default is true
    -x, --exclude PATTERN            Exclude files that match the given pattern.
                                     Can specify more than once, file is excluded if any pattern matches
    -v, --[no-]verbose               Be verbose
        --debug                      Show debug output.  Also enables verbose.
    -t, --threads NUM                Number of threads to spawn, useful for transcoding.
                                     Default: 1
        --set-aa ALBUM_ARTIST        Set the album_artist for all tracks
    -V, --version                    Disply the version and exit
    -y, --yes                        Don't ask before running.
    -h, --help                       Show this message
