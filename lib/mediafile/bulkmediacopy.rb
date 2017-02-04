# vim:et sw=2 ts=2

require 'mediafile'
module MediaFile;
class BulkMediaCopy
  include ::MediaFile
  def initialize(source,
                 album_artist: nil,
                 destination_root: ".",
                 progress: false,
                 transcode: {},
                 verbose: false,
                 debug: false
                )
    source =
      case source
      when String
        [source]
      when Array
        source
      else
        raise "Bad value for required first arg 'source': '#{source.class}'. " \
              'Should be String or Array.'
      end

    @copies             = Hash.new { |h,k| h[k] = [] }
    @destination_root   = destination_root
    @verbose            = verbose
    @debug              = debug
    @progress           = progress
    @album_artist       = album_artist
    @work               = get_work(source)
    @width              = [@work.count.to_s.size, 2].max
    @name_width         = @work.max{ |a,b| a.name.size <=> b.name.size }.name.size
    @transcode          = transcode
    @count              = 0
    @failed             = []
  end

  def run(max=4)
    start = Time.new
    debug "Call run with max => '#{max}'"
    puts "%#{@width + 8}s, %#{@width + 8}s,%#{@width + 9}s :: Mode" % [
      "Remaining",
      "Workers",
      "Complete"
    ]
    puts "%#{@width}d ( 100%%), %#{@width}d (%4.1f%%), %#{@width}d ( 0.0%%) :: *wait*" % [
      @work.count,
      0,
      0,
      0
    ]
    max > 1 ? mcopy(max) : scopy
    stop = Time.new
    duration = stop - start
    puts "Copied #{@count} files in #{ "%d:%d:%d:%d" % duration.to_duration} " +
      "(~%.2f songs/second))." % [(@count/duration)]
    dupes = @copies.select{ |_k,a| a.size > 1 }
    if dupes.any?
      puts "dupes"
      require 'pp'
      pp dupes
    end
    if @failed.any?
      puts "Some files failed to transfer."
      @failed.each { |f| puts f.to_s }
    end
  end

  private

  def get_work(source)
    source.map { |s|
      MediaFile.new(
        s,
        base_dir: @destination_root,
        force_album_artist: @album_artist,
        verbose: @verbose,
        debug: @debug,
      )
    }
  end

  def mcopy(max)
    raise "Argument must repond to :times" unless max.respond_to? :times
    raise "I haven't any work..." unless @work
    initialize_threads(max)
    queue = Queue.new
    @work.each { |s| queue << s }
    threads = []
    max.times do
      threads << Thread.new do
        while ( s = queue.pop(true) rescue nil)
          copy s
        end
      end
    end
    threads.each { |t| t.join }
    cleanup
  end

  def scopy
    raise "I haven't any work..." unless @work
    @work.each do |f|
      copy f
    end
  end

  def copy(mediafile)
    dest = mediafile.out_path transcode_table: @transcode
    lock {
      return unless copy_check? mediafile.source_md5, mediafile.source, dest
      @count += 1
      if @progress
        left  = @work.count - @count
        left_perc = left == 0 ? left : left.to_f / @work.count * 100
        cur = @copies.count - @count
        cur_perc = cur == 0 ? cur : cur.to_f / left * 100 # @work.count * 100
        c = cur_perc == 100
        finished = @count.to_f / @work.count * 100
        f = finished == 100.0
        action = case
                 when File.exists?(dest)
                   'target already exists'
                 when @transcode[mediafile.type]
                   'transcode'
                 else
                   'copy'
                 end
        print "%#{@width}d (%4.1f%%), %#{@width}d (%4.#{c ? 0 : 1}f%%), " \
          "%#{@width}d (%4.#{f ? 0 : 1}f%%) :: *%-s*\n    source file => %-s\n    " \
          "destination => %-s\n" % [
            left,
            left_perc,
            cur,
            cur_perc,
            @count,
            finished,
            action,
            (mediafile.source),
            mediafile.out_path(transcode_table:@transcode)
        ]
      end
      debug "#{mediafile.type} == #{@transcode[mediafile.type]}"
    }
    err = false
    begin
      mediafile.copy transcode_table: @transcode
    rescue => e
      debug("mediafile.copy failed.  #{e}")
      @failed << mediafile
      err = true
      raise
    end
    err
  end

  def copy_check?(md5,name,dest)
    # if multi-threaded, need to lock before calling
    @copies[md5] << "#{name} => #{dest}"
    # return true if this is the only one
    @copies[md5].count == 1
  end

end
end

