# vim:et sw=2 ts=2

require 'mediafile'
module MediaFile; class MediaFile
  include ::MediaFile

  attr_reader :source, :type, :name, :base_dir

  def initialize(path,
                 base_dir: '.',
                 force_album_artist: nil,
                 verbose: false,
                 debug: false)
    @base_dir = base_dir
    @destinations = Hash.new{ |k,v| k[v] = {} }
    @force_album_artist = force_album_artist
    @name     = File.basename( path, File.extname( path ) )
    @source   = path
    @type     = path[/(\w+)$/].downcase.to_sym
    @verbose  = verbose
    @debug    = debug
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
    lock{
      if File.exists?(destination)
        warn "File has already been transfered #{@source} => #{destination}" if @verbose
        return
      end
      if File.exists?(temp_dest)
        warn "File transfer is already in progress for #{@source} => #{temp_dest} => #{destination}"
        warn "This shouldn't happen!  Check to make sure it was really copied."
        return
      end
      FileUtils.mkdir_p File.dirname destination
      FileUtils.touch temp_dest
    }
    begin
      transcode_table.has_key?(@type) ?
        transcode(transcode_table, temp_dest) :
        really_copy(@source, temp_dest)
      FileUtils.mv temp_dest, destination
    rescue => e
      FileUtils.rm temp_dest if File.exists? temp_dest
      raise e
    end
  ensure
    FileUtils.rm temp_dest if File.exists? temp_dest
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

  def really_copy(src,dest)
    FileUtils.cp(src, dest)
    set_album_artist(dest)
    set_comment_and_title(dest)
  end

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
      safe_print "Attempting to transcode to the same format #{@source} from #{@type} to #{to}"
    end
    FileUtils.mkdir_p File.dirname destination

    decoder = set_decoder

    encoder = set_encoder(to, destination)

    safe_print "Decoder: '#{decoder.join(' ')}'\nEncoder: '#{encoder.join(' ')}'" if @verbose

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
      safe_print "Timeout exceeded!\n" << tpids.map { |p|
        Process.kill 15, p
        Process.kill 9, p
        "#{p} #{Process.wait2( p )[1]}"
      }.join(", ")
      FileUtils.rm [destination]
      raise
    end
    if err.any?
      safe_print "###\nError transcoding #{@source}: #{err.map{ |it,stat|
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
        [@album_artist, @album].map { |word|
          clean_string(word)
        }
      )
    )
  end

  def new_file_name
    # this doesn't include the extension.
    @newname ||= (
      read_tags
      bool = true
      file = clean_string(
        case
        when (@disc_number && (@track > 0) && @title) && !(@disc_total && @disc_total == 1)
          "%1d_%02d-" % [@disc_number, @track] + @title
        when (@track > 0 && @title)
          "%02d-" % @track + @title
        when @title && @title != ""
          @title
        else
          @name
        end
      )
    )
  end

  def clean_string(my_string)
    my_string ||= ""
    t = my_string.gsub(
      /^\.+|\.+$/,""
    ).gsub(
      /\//,"_"
    ).gsub(
      /\s/,"_"
    ).gsub(
      /[,:;)\]\[('"@$^*<>?!=]/,""
    ).gsub(
      /^[.]/,''
    ).gsub(
      /_?[&]_?/,"_and_"
    ).split('_').map{ |c|
      puts "DEBUG: capitalize: '#{c}'" if @debug
       "_and_" == c ? c : c.capitalize 
    }.join('_').gsub(
      /__+/,'_'
    ).gsub(/^[.]/, '')
    puts "DEBUG: clean_string: '#{my_string} => '#{t}'" if @debug
    t == "" ? "UNKNOWN" : t
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

  def set_album_artist(file)
    type = file[/(\w+)$/].downcase.to_sym
    return unless @force_album_artist
    case type
    when :m4a
      TagLib::MP4::File.open(file) do |f|
        f.tag.item_list_map.insert("aART", TagLib::MP4::Item.from_string_list([@force_album_artist]))
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
        if tag = f.id3v2_tag
          frame = TagLib::ID3v2::TextIdentificationFrame.new("TPE2", TagLib::String::UTF8)
          frame.text = @force_album_artist
          tag.add_frame(frame)
          f.save
        else
          safe_print("##########\nNo tag returned for #{@name}: #{@source}\n#############\n\n")
        end
      end
    end
  end

  def set_comment_and_title(file)
    klass = (@type == :mp3) ? TagLib::MPEG::File : TagLib::FileRef
    method = (@type == :mp3) ? :id3v2_tag : :tag

    klass.send(:open, file) do |f|
      tag = if (@type == :mp3)
              f.send(method, true)
            else
              f.send(method)
            end
      tag.comment = "#{@comment}"
      tag.title = (@title || @name.gsub('_',' ')) unless tag.title && tag.title != ""
      if (@type == :mp3)
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
    @comment = "MediaFile from source: #{@source}\n"
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
    puts "DEBUG: album:'#{@album}', artist:'#{@artist}'" +
      " @title:'#{@title}'  @genre:'#{@genre}'  @year:'#{@year}'" if @debug
    @red = true
  end
end; end

