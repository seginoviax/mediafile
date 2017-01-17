# vim:et sw=2 ts=2

require 'mediafile'

module MediaFile
class MediaFile
  include ::MediaFile

  attr_reader :source, :type, :name, :base_dir

  def initialize(full_path,
                 base_dir: '.',
                 force_album_artist: nil,
                 verbose: false,
                 debug: false)
    @base_dir = base_dir
    @destinations = Hash.new{ |k,v| k[v] = {} }
    @force_album_artist = force_album_artist
    @name     = File.basename( full_path, File.extname( full_path ) )
    @source   = full_path
    @type     = full_path[/(\w+)$/].downcase.to_sym
    @verbose  = verbose
    @debug    = debug
    @cover = File.join(
      File.dirname(full_path),
      'cover.jpg')
    @cover = nil unless File.exist?(@cover)
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
    temp_dest = tmp_path base_dir: dest, typ: transcode_table[@type]
    debug "temp dest is '#{temp_dest}'"
    lock{
      if File.exist?(temp_dest)
        error "File transfer is already in progress for #{@source} => #{temp_dest} => #{destination}"
        error "This shouldn't happen!  Check to make sure it was really copied."
        raise
        #return
      end
      if File.exist?(destination)
        info("File has already been transfered #{@source} => #{destination}")
        return
      end
      debug("Create parent directories at '#{File.dirname destination}'.")
      FileUtils.mkdir_p File.dirname destination
      FileUtils.touch temp_dest
    }
    begin
      transcode_table.has_key?(@type) ?
        transcode(transcode_table, temp_dest) :
        FileUtils.cp(@source, temp_dest)
      set_album_artist(temp_dest)
      set_comment_and_title(temp_dest)
      set_cover_art(temp_dest)
      FileUtils.mv temp_dest, destination
    rescue => e
      FileUtils.rm temp_dest if File.exist? temp_dest
      raise e
    end
  ensure
    FileUtils.rm temp_dest if File.exist? temp_dest
  end

  def to_s
    "#{@source}"
  end

  def self.tags(*args)
    private
    args.each do |arg|
      define_method arg do
        read_tags
        instance_variable_get "@#{arg}"
      end
    end
  end

  private

  tags :album, :artist, :album_artist,
       :title, :genre, :year, :track,
       :comment, :disc_number, :disc_total

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
    encoder = case to
              when :flac
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
                  #raise "Please don't transcode to flac.  It is broken right now"
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
                raise "Unknown target '#{to}'.  Cannot set encoder."
              end
    debug "Encoder set to '#{encoder}'"
    encoder
  end

  def transcode(trans , destination)
    to = trans[@type]
    if to == @type
      error "Attempting to transcode to the same format #{@source} from #{@type} to #{to}"
    end
    FileUtils.mkdir_p File.dirname destination

    decoder = set_decoder

    encoder = set_encoder(to, destination)

    info "Decoder: '#{decoder.join(' ')}'\nEncoder: '#{encoder.join(' ')}'"

    pipes = Hash[[:encoder,:decoder].zip IO.pipe]
    #readable, writeable = IO.pipe
    pids = {
      spawn(*decoder, :out=>pipes[:decoder], :err=>"/tmp/decoder.err") => :decoder,
      spawn(*encoder, :in =>pipes[:encoder], :err=>"/tmp/encoder.err") => :encoder,
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
            _p, stat = Process.wait2 pid, Process::WNOHANG
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
      error "Timeout exceeded!\n" << tpids.map { |p|
        Process.kill 15, p
        Process.kill 9, p
        "#{p} #{Process.wait2( p )[1]}"
      }.join(", ")
      FileUtils.rm [destination]
      raise
    end
    if err.any?
      error "###\nError transcoding #{@source}: #{err.map{ |it,stat|
        "#{it} EOT:#{stat.exitstatus} #{stat}" }.join(" and ") }\n###\n"
      raise
    end
  end

  # directory names cannot end with a '.'
  # it breaks windows (really!)

  def relative_path
    @relpath ||= (
      read_tags
      File.join(
        [@album_artist, @album].map { |word|
          debug word
          clean_string word
        }
      )
    )
  end

  def new_file_name
    # this doesn't include the extension.
    @newname ||= (
      read_tags
      case
      when (@disc_number && (@track > 0) && @title) && !(@disc_total && @disc_total == 1)
        "%1d_%02d-" % [@disc_number, @track] + clean_string(@title)
      when (@track > 0 && @title)
        "%02d-" % @track + clean_string(@title)
      when @title && @title != ""
        clean_string(@title)
      else
        clean_string(@name)
      end
    )
  end

  def clean_string(my_string)
    my_string ||= ""
    t = my_string.gsub(
      /\.+|\.+$/,""
    ).gsub(
      /\/+|\s+/, '_'
    ).gsub(
      /[,:;)\]\[('"@$^*<>?!=]/,""
    ).gsub(
      /_?[&]_?/,"_and_"
    ).split('_').map{ |c|
      c.split('-').map{ |d|
        next if d[/_/]
        debug("capitalize: '#{d}'")
        d.capitalize
      }.join('-')
    }.join('_').gsub(
      /^[.]/, ''
    ).gsub(
      /_+/, '_'
    )
    t == "" ? "UNKNOWN" : t
    debug("clean_string: '#{my_string} => '#{t}'")
    t
  end

  def tmp_file_name
    "." + new_file_name
  end

  def tmp_path(base_dir: @base_dir, typ: nil)
    typ ||= @type
    File.join(
      base_dir,
      relative_path,
      tmp_file_name,
    ) << ".#{typ}"
  end

  def has_cover_art?(file)
    typ = file[/(\w+)$/].downcase.to_sym
    debug("Checking if #{file} has clover art. (#{typ})")
    case typ
    when :m4a
      return true if file.tag.item_list_map['covr'].to_cover_art_list.find do |p|
        p.format == TagLib::MP4::CoverArt::JPEG
      end
    when :flac
      debug("It does.")
      TagLib::FLAC::File.open(file) do |f|
        return true if f.picture_list.find do |p|
          p.type == TagLib::FLAC::Picture::FrontCover
        end
      end
    when :mp3
      TagLib::MPEG::File.open(file) do |f|
        tag = f.id3v2_tag
        # Don't overwrite an existing album cover.
        debug("Checking if the target mp3 file already has a cover.")
        return true if tag.frame_list('APIC').find do |p|
          p.type == TagLib::ID3v2::AttachedPictureFrame::FrontCover
        end
      end
    end
    false
  end

  def set_cover_art(file)
    debug("Checking for cover to apply to #{file}")
    return if has_cover_art?(file)
    write_cover_data(file, get_cover_data)
  end

  def get_cover_data
    info("Getting cover art from #{@source}.")
    #  This is bad maybe
    @cover ? File.open(@cover, 'rb') { |c| c.read } :
    case @type
    when :m4a
      TagLib::MP4::File.open(@source) do
        mp4.tag.item_list_map['covr'].to_cover_art_list.first.data
      end
    when :flac
      TagLib::FLAC::File.open(@source) do |f|
        info("Geting cover art from #{@source}.")
        f.picture_list.find { |p| p.type == TagLib::FLAC::Picture::FrontCover }.data
      end
    when :mp3
      TagLib::MPEG::File.open(@source) do |f|
        tag = f.id3v2_tag
        tag.frame_list('APIC').first.picture
      end
    else
      error "Unsupported file type '#{@type}'.  Not adding cover art from '#{@cover}'."
      false
    end
  end

  def write_cover_data(file, cover_art)
    typ = file[/(\w+)$/].downcase.to_sym
    case typ
    when :m4a
      TagLib::MP4::File.open(file) do
        c = TagLib::MP4::CoverArt.new(TagLib::MP4::CoverArt::JPEG, cover_art)
        item = TagLib::MP4::Item.from_cover_art_list([c])
        file.tag.item_list_map.insert('covr', item)
        file.save
      end
    when :flac
      TagLib::FLAC::File.open(file) do |f|
        pic = TagLib::FLAC::Picture.new
        pic.type = TagLib::FLAC::Picture::FrontCover
        pic.mime_type = 'image/jpeg'
        pic.description = 'Cover'
        pic.width = 90
        pic.height = 90
        pic.data = cover_art
        info("Adding cover art tag to #{file}.")
        f.add_picture(cover_art)
        f.save
      end
    when :mp3
      TagLib::MPEG::File.open(file) do |f|
        tag = f.id3v2_tag
        apic = TagLib::ID3v2::AttachedPictureFrame.new
        apic.mime_type = 'image/jpeg'
        apic.description = 'Cover'
        apic.type = TagLib::ID3v2::AttachedPictureFrame::FrontCover
        apic.picture = cover_art
        tag.add_frame(apic)
        f.save
      end
    else
      error "Unsupported file type '#{typ}'.  Not adding cover art from '#{@cover}'."
      false
    end
  end

  def set_album_artist(file)
    return unless @force_album_artist
    typ = file[/(\w+)$/].downcase.to_sym
    case typ
    when :m4a
      TagLib::MP4::File.open(file) do |f|
        f.tag.item_list_map.insert("aART",
                                   TagLib::MP4::Item.from_string_list([@force_album_artist]))
        f.save
      end
    when :flac
      TagLib::FLAC::File.open(file) do |f|
        tag = f.xiph_comment
        ['ALBUMARTIST', 'ALBUM ARTIST', 'ALBUM_ARTIST'].select do |t|
          tag.add_field(t, @force_album_artist)
        end
        f.save
      end
    when :mp3
      TagLib::MPEG::File.open(file) do |f|
        tag = f.id3v2_tag
        if tag
          frame = TagLib::ID3v2::TextIdentificationFrame.new("TPE2", TagLib::String::UTF8)
          frame.text = @force_album_artist
          tag.add_frame(frame)
          f.save
        else
          error("##########\nNo tag returned for #{@name}: #{@source}\n#############\n\n")
        end
      end
    end
  end

  def set_comment_and_title(file)
    debug "file is #{file}"
    typ = file[/(\w+)$/].downcase.to_sym
    klass  = (typ == :mp3) ? TagLib::MPEG::File : TagLib::FileRef
    method = (typ == :mp3) ? :id3v2_tag : :tag

    klass.send(:open, file) do |f|
      tag = if (typ == :mp3)
              f.send(method, true)
            else
              f.send(method)
            end
      tag.comment = "#{@comment}"
      tag.title = (@title || @name.tr('_',' ')) unless tag.title && tag.title != ""
      if (typ == :mp3)
        f.save(TagLib::MPEG::File::ID3v2)
      else
        f.save
      end
    end
  end

  def read_tags
    return if @red
    @album = nil
    @artist= nil
    @title = nil
    @genre = nil
    @year = nil
    @track = 0
    @comment = "MediaFile source: #{@source}\n"
    TagLib::FileRef.open(@source) do |file|
      unless file.null?
        tag = file.tag
        @album  = tag.album   if tag.album && tag.album != ""
        @artist = tag.artist  if tag.artist && tag.artist != ""
        @title  = tag.title   if tag.title && tag.title != ""
        @genre  = tag.genre   if tag.genre && tag.genre != ""
        @comment+= tag.comment if tag.comment && tag.comment != ""
        @track  = tag.track   if tag.track && tag.track != ""
        @year   = tag.year    if tag.year && tag.year != ""
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
        tag = file.xiph_comment
        if tag
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
    debug("album:'#{@album}', artist:'#{@artist}'" +
      " title:'#{@title}'  genre:'#{@genre}'  year:'#{@year}'")
    @red = true
  end
end
end

