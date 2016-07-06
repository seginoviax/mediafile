#!/usr/bin/env ruby
# vim:et sw=2 ts=2

module MediaFile; class MediaFile

  attr_reader :source, :type, :name, :base_dir

  def initialize(path,
                 base_dir: '.',
                 force_album_artist: nil,
                 printer: proc {|msg| puts msg},
                 verbose: false)
    @base_dir = base_dir
    @destinations = Hash.new{ |k,v| k[v] = {} }
    @force_album_artist = force_album_artist
    @name     = File.basename( path, File.extname( path ) )
    @printer  = printer
    @source   = path
    @type     = path[/(\w+)$/].downcase.to_sym
    @verbose  = verbose
  end

  def source_md5
    @source_md5 ||= Digest::MD5.hexdigest( @source )
  end

  def out_path(base_dir: @base_dir, transcode_table: {})
    @destinations[base_dir][transcode_table] ||= File.join(
      base_dir,
      relative_path,
      new_file_name,
    ) << ".#{transcode_table[@type] || @type}"
  end

  def copy(dest: @base_dir, transcode_table: {})
    destination = out_path base_dir: dest, transcode_table: transcode_table
    temp_dest = tmp_path base_dir: dest, transcode_table: transcode_table
    unless File.exists? destination
      FileUtils.mkdir_p File.dirname destination
      begin
        transcode_table.has_key?(@type) ?
          transcode(transcode_table, temp_dest) :
          FileUtils.cp(@source, temp_dest)
        FileUtils.mv temp_dest, destination
      rescue => e
        FileUtils.rm temp_dest if File.exists? temp_dest
        raise e
      end
    end
  end

  def printit(msg)
    @printer.call msg
  end

  def to_s
    "#{@source}"
  end

  def self.tags(*args)
    args.each do |arg|
      define_method arg do
        read_tags
        instance_variable_get "@#{arg}"
      end
    end
  end

  tags :album, :artist, :album_artist,
       :title, :genre, :year, :track,
       :comment, :disc_number, :disc_total

  private

  def set_decoder()
    case @type
    when :flac
      %W{flac -c -s -d #{@source}}
    when :mp3
      #%W{lame --decode #{@source} -}
      %W{sox #{@source} -t wav -}
    when :m4a
      %W{ffmpeg -i #{@source} -f wav -}
    when :wav
      %W{cat #{@source}}
    else
      raise "Unknown type '#{@type}'.  Cannot set decoder"
    end
  end

  def set_encoder(to,destination)
    comment = "; Transcoded by MediaFile on #{Time.now}"
    case to
    when :flac
      raise "Please don't transcode to flac.  It is broken right now"
      %W{flac -7 -V -s -o #{destination}} +
        (@artist ?  ["-T", "artist=#{@artist}"]       : [] ) +
        (@title  ?  ["-T", "title=#{@title}"]         : [] ) +
        (@album  ?  ["-T", "album=#{@album}"]         : [] ) +
        (@track > 0 ? ["-T", "tracknumber=#{@track}"] : [] ) +
        (@year   ?  ["-T", "date=#{@year}"]           : [] ) +
        (@genre  ?  ["-T", "genre=#{@genre}"]         : [] ) +
        ["-T", "comment=" + @comment + comment ] +
        (@album_artist ? ["-T", "albumartist=#{@album_artist}"] : [] ) +
        (@disc_number ? ["-T", "discnumber=#{@disc_number}"] : [] ) +
        ["-"]
    when :mp3
      %W{lame --quiet --preset extreme -h --add-id3v2 --id3v2-only} +
        (@title  ?  ["--tt", @title] : [] ) +
        (@artist ?  ["--ta", @artist]: [] ) +
        (@album  ?  ["--tl", @album] : [] ) +
        (@track > 0 ? ["--tn", @track.to_s]: [] ) +
        (@year   ?  ["--ty", @year.to_s ] : [] ) +
        (@genre  ?  ["--tg", @genre ]: [] ) +
        ["--tc",  @comment + comment ] +
        (@album_artist ? ["--tv", "TPE2=#{@album_artist}"] : [] ) +
        (@disc_number ? ["--tv", "TPOS=#{@disc_number}"] : [] ) +
        ["-", destination]
    when :wav
      %W{dd of=#{destination}}
    else
      raise "Unknown target '#{to}'.  Cannot set encoder"
    end
  end

  def transcode(trans , destination)
    to = trans[@type]
    if to == @type
      printit "Attempting to transcode to the same format #{@source} from #{@type} to #{to}"
    end
    FileUtils.mkdir_p File.dirname destination

    decoder = set_decoder

    encoder = set_encoder(to, destination)

    printit "Decoder: '#{decoder.join(' ')}'\nEncoder: '#{encoder.join(' ')}'" if @verbose

    pipes = Hash[[:encoder,:decoder].zip IO.pipe]
    #readable, writeable = IO.pipe
    pids = {
      spawn(*decoder, :out=>pipes[:decoder], :err=>"/dev/null") => :decoder,
      spawn(*encoder, :in =>pipes[:encoder], :err=>"/dev/null") => :encoder,
    }
    tpids = pids.keys
    err = []
    begin
      Timeout::timeout(60 * ( File.size(@source) / 1024 / 1024 /2 ) ) {
        #Timeout::timeout(3 ) {
        while tpids.any? do
          sleep 0.2
          tpids.delete_if do |pid|
            ret = false
            p, stat = Process.wait2 pid, Process::WNOHANG
            if stat
              pipes[pids[pid]].close unless pipes[pids[pid]].closed?
              ret = true
            end
            if stat and stat.exitstatus and stat.exitstatus != 0
              err << [ pids[pid], stat ]
            end
            ret
          end
        end
      }
    rescue Timeout::Error
      printit "Timeout exceeded!\n" << tpids.map { |p|
        Process.kill 15, p
        Process.kill 9, p
        "#{p} #{Process.wait2( p )[1]}"
      }.join(", ")
      FileUtils.rm [destination]
      raise
    end
    if err.any?
      printit "###\nError transcoding #{@source}: #{err.map{ |it,stat|
        "#{it} EOT:#{stat.exitstatus} #{stat}" }.join(" and ") }\n###\n"
      exit 1
    end
  end

  # directory names cannot end with a '.'
  # it breaks windows (really!)

  def relative_path
    @relpath ||= (
      read_tags
      dest = File.join(
        [(@album_artist||"UNKNOWN"), (@album||"UNKNOWN")].map { |word|
          word.gsub(/^\.+|\.+$/,"").gsub(/\//,"_")
        }
      )
      bool=true
      dest.gsub(/\s/,"_").gsub(/[,:)\]\[('"@$^*<>?!]/,"").gsub(/_[&]_/,"_and_").split('').map{ |c|
        b = bool; bool = c.match('/|_'); b ? c.capitalize : c
      }.join('').gsub(/__+/,'_')
    )
  end

  def new_file_name
    # this doesn't include the extension.
    @newname ||= (
      read_tags
      bool = true
      file = (
        case
        when (@disc_number && (@track > 0) && @title) && !(@disc_total && @disc_total == 1)
          "%1d_%02d-" % [@disc_number, @track] + @title
        when (@track > 0 && @title)
          "%02d-" % @track + @title
        when @title
          @title
        else
          @name
        end
      ).gsub(
        /^\.+|\.+$/,""
      ).gsub(
        /\//,"_"
      ).gsub(
        /\s/,"_"
      ).gsub(
        /[,:)\]\[('"@$^*<>?!]/,""
      ).gsub(
        /_[&]_/,"_and_"
      ).split('').map{ |c|
                    b = bool; bool = c.match('/|_'); b ? c.capitalize : c
                  }.join('').gsub(/__+/,'_')
    )
  end

  def tmp_file_name
    "." + new_file_name
  end

  def tmp_path(base_dir: @base_dir, transcode_table: {})
    File.join(
      base_dir,
      relative_path,
      tmp_file_name,
    ) << ".#{transcode_table[@type] || @type}"
  end

  def read_tags
    return if @red
    @album = @artist= @title = @genre = @year = nil
    @track = 0
    @comment = ""
    TagLib::FileRef.open(@source) do |file|
      unless file.null?
        tag = file.tag
        @album  = tag.album   if tag.album
        @artist = tag.artist  if tag.artist
        @title  = tag.title   if tag.title
        @genre  = tag.genre   if tag.genre
        @comment= tag.comment if tag.comment
        @track  = tag.track   if tag.track
        @year   = tag.year    if tag.year
      end
    end
    @album_artist = @artist
    case @type
    when :m4a
      TagLib::MP4::File.open(@source) do |file|
        @disc_number = file.tag.item_list_map["disk"] ?
                       file.tag.item_list_map["disk"].to_int_pair[0] :
                       nil
        @album_artist = file.tag.item_list_map["aART"] ?
                        file.tag.item_list_map["aART"].to_string_list[0]
                        : @album_artist
      end
    when :flac
      TagLib::FLAC::File.open(@source) do |file|
        if tag = file.xiph_comment
          [
            [:@album_artist, ['ALBUMARTIST', 'ALBUM ARTIST', 'ALBUM_ARTIST'], :to_s ],
            [:@disc_number,  ['DISCNUMBER'], :to_i ],
            [:@disc_total,   ['DISCTOTAL'], :to_i ]
          ].each do |field,list,func|
            val = list.collect{ |i| tag.field_list_map[i] }.select{|i| i }.first
            instance_variable_set(field, val[0].send(func)) if val
          end
        end
      end
    when :mp3
      TagLib::MPEG::File.open(@source) do |file|
        tag = file.id3v2_tag
        if tag
          [[:@album_artist, 'TPE2', :to_s], [:@disc_number, 'TPOS', :to_i]].each do |field,list,func|
            if tag.frame_list(list).first and tag.frame_list(list).first.to_s.size > 0
              instance_variable_set(field, "#{tag.frame_list(list).first}".send(func) )
            end
          end
        end
      end
    end
    if @force_album_artist
      @album_artist = @force_album_artist
    else
      @album_artist ||= @artist
    end
    @red = true
  end
end; end

