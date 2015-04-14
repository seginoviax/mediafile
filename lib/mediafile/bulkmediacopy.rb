module MediaFile; class BulkMediaCopy
  def initialize( source, destination_root: ".", verbose: false, progress: false, transcode: {}  )
    source = case source
      when String
        [source]
      when Array
        source
      else
        raise "Bad value for required first arg 'source': '#{source.class}'.  Should be String or Array."
      end

    @copies             = Hash.new { |h,k| h[k] = [] }
    @destination_root   = destination_root
    @verbose            = verbose
    @progress           = progress
    @work               = source.map { |s|
                            MediaFile.new(s,
                              base_dir: @destination_root,
                              verbose: @verbose,
                              printer: proc{ |msg| self.safe_print( msg ) }
                            )
                          }
    @width              = [@work.count.to_s.size, 2].max
    @name_width         = @work.max{ |a,b| a.name.size <=> b.name.size }.name.size
    @transcode          = transcode
    @count              = 0
    @failed             = []
  end

  def run(max=4)
    puts "%#{@width + 8}s, %#{@width + 8}s,%#{@width + 8}s, %-#{@name_width}s => Destination Path" % [
      "Remaining",
      "Workers",
      "Complete",
      "File Name"
    ]
    puts "%#{@width}d ( 100%%), %#{@width}d (%4.1f%%), %#{@width}d ( 0.0%%)" % [
      @work.count,
      0,
      0,
      0
    ]
    max > 1 ? mcopy(max) : scopy
    dupes = @copies.select{ |k,a| a.size > 1 }
    if dupes.any?
      puts "dupes"
      require 'pp'
      pp dupes
    end
    if @failed.any?
      puts "Some files timed out"
      @failed.each { |f| puts f.to_s }
    end
  end

  def safe_print(message='')
    locked {
      print block_given? ? yield : message
    }
  end

  private

  def locked
    if @semaphore
      @semaphore.synchronize {
        yield
      }
    else
      yield
    end
  end

  def mcopy(max)
    raise "Argument must repond to :times" unless max.respond_to? :times
    raise "I haven't any work..." unless @work
    require 'thread'
    @semaphore = Mutex.new
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
    @semaphore = nil
  end

  def scopy
    raise "I haven't any work..." unless @work
    @work.each do |f|
      copy f
    end
  end

  def copy(mediafile)
    dest = mediafile.out_path transcode_table: @transcode
    locked {
      return unless copy_check? mediafile.source_md5, mediafile.source, dest
    }

    err = false
    begin
      mediafile.copy transcode_table: @transcode
    rescue Timeout::Error
      @failed << mediafile
      err = true
    end

    locked {
      @count += 1
      if @progress
        left  = @work.count - @count
        left_perc = left == 0 ? left : left.to_f / @work.count * 100
        cur   = @copies.count - @count
        cur_perc = cur == 0 ? cur : cur.to_f / left * 100 # @work.count * 100
        c = cur_perc == 100
        finished = @count.to_f / @work.count * 100
        f = finished == 100.0
        puts "%#{@width}d (%4.1f%%), %#{@width}d (%4.#{c ? 0 : 1}f%%), %#{@width}d (%4.#{f ? 0 : 1}f%%) %-#{@name_width}s => %-s" % [
          left,
          left_perc,
          cur,
          cur_perc,
          @count,
          finished,
          (mediafile.name + (err ? " **" : "") ),
          mediafile.out_path(transcode_table:@transcode)
        ]
      end
    }

  end

  def copy_check?(md5,name,dest)
    # if multi-threaded, need to lock before calling
    @copies[md5] << "#{name} => #{dest}"
    # return true if this is the only one
    @copies[md5].count == 1
  end

end; end

