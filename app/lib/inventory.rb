# frozen_string_literal: true

require 'aws-sdk-s3'
require 'csv'
require 'net/http'
require 'uri'
require 'stringio'

## Track inventory statistics for the portion of the inventory being analyzed
class Inventory
  CACHE_MANIFEST = 'manifests'
  CACHE_INVENTORY = 'inventory'
  CACHE_INVENTORY_FILE = 'inventory-file.csv'
  CACHE_METADATA = 'metadata'
  CACHE_METADATA_FILE = 'metadata-file.csv'

  def initialize(iconfig)
    @filepath = InventoryConfig::INVENTORY_LOCALFILE
    @iconfig = iconfig
    @last_updated = nil
    @metadata = {}
    reset
  end

  def reset
    @dirs = {}
    @prefixes = []
  end

  def metadata_record
    {
      primary_identifier: nil,
      local_identifier: nil,
      title: nil,
      creator: nil,
      date: nil
    }
  end

  def get_inventory_csv
    if @iconfig.cache_bucket.empty?
      inventory_file_init unless File.exist?(@filepath)
      @last_updated = File.mtime(@filepath)
      File.read(@filepath)
    else
      begin
        s3_client = Aws::S3::Client.new(
          region: ENV.fetch('AWS_REGION', 'us-west-2')
        )
        obj = s3_client.get_object(
          bucket: @iconfig.cache_bucket,
          key: "#{@iconfig.project}/#{CACHE_INVENTORY}/#{CACHE_INVENTORY_FILE}"
        )
        @last_updated = obj.last_modified
        obj.body.read
      rescue Aws::S3::Errors::NoSuchKey
        inventory_file_init
        @last_updated = File.mtime(@filepath)
        File.read(@filepath)
      end
    end
  end

  def get_metadata_csv
    if @iconfig.cache_bucket.empty?
      metadata_file_init unless File.exist?(InventoryConfig::METADATA_LOCALFILE)
      File.read(InventoryConfig::METADATA_LOCALFILE)
    else
      begin
        s3_client = Aws::S3::Client.new(
          region: ENV.fetch('AWS_REGION', 'us-west-2')
        )
        obj = s3_client.get_object(
          bucket: @iconfig.cache_bucket,
          key: "#{@iconfig.project}/#{CACHE_METADATA}/#{CACHE_METADATA_FILE}"
        )
        obj.body.read
      rescue Aws::S3::Errors::NoSuchKey
        metadata_file_init
        File.read(InventoryConfig::METADATA_LOCALFILE)
      end
    end
  end

  def load_inventory_csv
    reset
    CSV.parse(get_inventory_csv, headers: true, col_sep: "\t", row_sep: "\n") do |row|
      key = row['key']
      size = row['size'].to_i
      last_modified = row['last_modified']
      add(key, size, last_modified)
    end
  end

  def load_metadata_csv
    @metadata = {}
    CSV.parse(get_metadata_csv, headers: true, col_sep: ',', row_sep: "\n") do |row|
      key = row['key']
      @metadata[key] = {
        primary_identifier: row['primary_identifier'],
        local_identifier: row['local_identifier'],
        creator: row['creator'],
        title: row['title'],
        date: row['date']
      }
    end
  end

  def inventory_file_init
    `mkdir -p #{File.dirname(@filepath)}`
    CSV.open(@filepath, 'w', col_sep: "\t", row_sep: "\n") do |csv|
      csv << %w[key size last_modified]
    end
  end

  def metadata_file_init
    `mkdir -p #{File.dirname(InventoryConfig::METADATA_LOCALFILE)}`
    CSV.open(InventoryConfig::METADATA_LOCALFILE, 'w', col_sep: ',', row_sep: "\n") do |csv|
      csv << %w[key primary_identifier local_identifier creator title date]
    end
  end

  def add(key, size, last_modified)
    return if key.nil?
    return if key.empty?

    # return unless key.start_with?(path)

    size = 0 if size.nil?
    current_path = key
    parent_path = File.dirname(key) == '.' ? '' : File.dirname(key)
    ext = File.extname(key).downcase

    @dirs[parent_path] ||= { count: 0, bytes: 0, files: [], extensions: {}, prefixes: [] }
    @dirs[parent_path][:count] += 1
    @dirs[parent_path][:bytes] += size
    @dirs[parent_path][:extensions][ext] ||= { count: 0, bytes: 0 }
    @dirs[parent_path][:extensions][ext][:count] += 1
    @dirs[parent_path][:extensions][ext][:bytes] += size
    @dirs[parent_path][:files] << { key: current_path, size: size, last_modified: last_modified }
    add_prefix(parent_path) unless parent_path.empty?
  end

  def add_prefix(ppath)
    gparent_path = File.dirname(ppath) == '.' ? '' : File.dirname(ppath)
    return unless gparent_path != ppath

    @dirs[gparent_path] ||= { count: 0, bytes: 0, files: [], extensions: {}, prefixes: [] }
    @dirs[gparent_path][:prefixes] << ppath unless @dirs[gparent_path][:prefixes].include?(ppath)
    add_prefix(gparent_path)
  end

  def save_inventory
    inventory_file_init
    CSV.open(@filepath, 'a', col_sep: "\t", row_sep: "\n") do |csv|
      @dirs.each_value do |dir_info|
        dir_info[:files].each do |file_info|
          csv << [file_info[:key], file_info[:size], file_info[:last_modified]]
        end
      end
    end
    unless @iconfig.cache_bucket.empty?
      save_object(
        "#{@iconfig.project}/#{CACHE_INVENTORY}/#{CACHE_INVENTORY_FILE}",
        File.read(@filepath)
      )
    end
    @last_updated = File.mtime(@filepath)
  end

  def save_metadata
    metadata_file_init
    CSV.open(InventoryConfig::METADATA_LOCALFILE, 'a', col_sep: ',', row_sep: "\n") do |csv|
      @metadata.each do |key, meta_info|
        csv << [
          key,
          meta_info[:primary_identifier],
          meta_info[:local_identifier],
          meta_info[:title],
          meta_info[:creator],
          meta_info[:date]
        ]
      end
    end
    return if @iconfig.cache_bucket.empty?

    save_object(
      "#{@iconfig.project}/#{CACHE_METADATA}/#{CACHE_METADATA_FILE}",
      File.read(InventoryConfig::METADATA_LOCALFILE)
    )
  end

  def save_object(key, body)
    s3_client = Aws::S3::Client.new(
      region: ENV.fetch('AWS_REGION', 'us-west-2')
    )
    s3_client.put_object(
      bucket: @iconfig.cache_bucket,
      key: key,
      body: body
    )
  end

  def self.format_int(vint)
    vint.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  def count
    @dirs.values.sum { |dir| dir[:count] }
  end

  def bytes
    @dirs.values.sum { |dir| dir[:bytes] }
  end

  def files(path)
    return [] unless @dirs.key?(path)

    @dirs[path][:files]
  end

  def descendant_files(path)
    files = files(path)
    prefixes(path).each do |prefix|
      files += descendant_files(prefix)
    end
    files
  end

  def descendant_files_by_depth(path, depth)
    depth_map = {}
    descendant_files(path).each do |file|
      fname = path.empty? ? file[:key] : file[:key][(path.length + 1)..]
      parent = File.dirname(fname) == '.' ? '' : File.dirname(fname)
      parentarr = parent.split('/')
      mapkey = if depth.positive? && parentarr.length >= depth
                 parentarr[0..(depth - 1)].join('/')
               elsif depth.negative? && parentarr.length >= depth.abs
                 parentarr[0..depth].join('/')
               else
                 'OTHER'
               end
      depth_map[mapkey] ||= []
      depth_map[mapkey] << file
    end
    depth_map
  end

  def extensions(path)
    return {} unless @dirs.key?(path)

    @dirs[path][:extensions]
  end

  def prefixes(path)
    return [] unless @dirs.key?(path)

    @dirs[path][:prefixes]
  end

  def dirs(path)
    return {} unless @dirs.key?(path)

    @dirs[path]
  end

  def path_count(path)
    total = dirs(path).fetch(:count, 0)
    prefixes(path).each do |prefix|
      total += path_count(prefix)
    end
    total
  end

  def path_bytes(path)
    total = dirs(path).fetch(:bytes, 0)
    prefixes(path).each do |prefix|
      total += path_bytes(prefix)
    end
    total
  end

  def path_depth(path)
    max_depth = 0
    prefixes(path).each do |prefix|
      max_depth = [max_depth, 1 + path_depth(prefix)].max
    end
    max_depth
  end

  def checkm(depth, objectformat, preview: true)
    return checkm_preview(depth) if preview
    return object_checkm(descendant_files(@iconfig.path), objectformat) if depth.empty?

    batch_buffer = StringIO.new
    batch_buffer.puts batch_checkm_header

    CSV.generate(col_sep: '|', row_sep: "\n", force_quotes: false) do |csv|
      descendant_files_by_depth(@iconfig.path, depth.to_i).each do |mapkey, files|
        mkey = manifest_key(depth, mapkey)
        @metadata[mkey] ||= metadata_record
        csv << [
          manifest_url(depth, mapkey),
          nil,
          nil,
          nil,
          nil,
          "#{File.basename(mapkey)}.checkm",
          @metadata[mkey][:primary_identifier],
          @metadata[mkey][:local_identifier],
          @metadata[mkey][:creator],
          @metadata[mkey][:title],
          @metadata[mkey][:date]
        ]
        object_buffer = StringIO.new
        object_buffer.puts object_checkm(files, objectformat)
        save_object(manifest_key(depth, mapkey), object_buffer.string)
      end
      batch_buffer.puts csv.string
    end

    save_metadata
    batch_buffer.puts %(#%eof)
    batch_buffer.string
  end

  def checkm_preview(depth = '')
    return object_checkm_preview if depth.empty?

    buffer = StringIO.new
    buffer.puts 'Manifest Checkm'
    buffer.puts "Path: #{@iconfig.path}"
    buffer.puts "Depth: #{depth}"
    buffer.puts ''

    descendant_files_by_depth(@iconfig.path, depth.to_i).each do |mapkey, files|
      buffer.puts manifest_url(depth, mapkey)
      files.each do |file|
        buffer.puts "  #{file_url(file[:key])}"
      end
    end
    buffer.string
  end

  def file_url(file)
    "https://#{@iconfig.bucket}.s3.#{@iconfig.region}.amazonaws.com/#{pathencode(file)}"
  end

  def manifest_key(_depth, mapkey)
    key = "#{@iconfig.project}/#{CACHE_MANIFEST}/"
    key += "#{pathencode(@iconfig.path)}/" unless @iconfig.path.empty?
    key += "#{pathencode(mapkey)}.checkm"
    key
  end

  def pathencode(path)
    path.split('/').map { |s| CGI.escape(s) }.join('/')
  end

  def manifest_url(_depth, mapkey)
    manifest = "https://#{@iconfig.cache_bucket}.s3.us-west-2.amazonaws.com/" \
               "#{@iconfig.project}/#{CACHE_MANIFEST}/"
    manifest += "#{pathencode(@iconfig.path)}/" unless @iconfig.path.empty?
    manifest += "#{pathencode(mapkey)}.checkm"
    manifest
  end

  def object_checkm_header
    %(#%checkm_0.7
#%profile | http://uc3.cdlib.org/registry/ingest/manifest/mrt-ingest-manifest
#%prefix | mrt: | http://merritt.cdlib.org/terms#
#%prefix | nfo: | http://www.semanticdesktop.org/ontologies/2007/03/22/nfo#
#%fields | nfo:fileUrl | nfo:hashAlgorithm | nfo:hashValue | nfo:fileSize | nfo:fileLastModified | nfo:fileName | mrt:mimeType)
  end

  def single_file_checkm_header
    %(#%checkm_0.7
#%profile | http://uc3.cdlib.org/registry/ingest/manifest/mrt-single-file-batch-manifest
#%prefix | mrt: | http://merritt.cdlib.org/terms#
#%prefix | nfo: | http://www.semanticdesktop.org/ontologies/2007/03/22/nfo#
#%fields | nfo:fileUrl | nfo:hashAlgorithm | nfo:hashValue | nfo:fileSize | nfo:fileLastModified | nfo:fileName | mrt:primaryIdentifier | mrt:localIdentifier | mrt:creator | mrt:title | mrt:date)
  end

  def batch_checkm_header
    %(#%checkm_0.7
#%profile | http://uc3.cdlib.org/registry/ingest/manifest/mrt-batch-manifest
#%prefix | mrt: | http://merritt.cdlib.org/terms#
#%prefix | nfo: | http://www.semanticdesktop.org/ontologies/2007/03/22/nfo#
#%fields | nfo:fileUrl | nfo:hashAlgorithm | nfo:hashValue | nfo:fileSize | nfo:fileLastModified | nfo:fileName | mrt:primaryIdentifier | mrt:localIdentifier | mrt:creator | mrt:title | mrt:date)
  end

  def object_checkm(files, objectformat)
    objmanifest = objectformat == 'mrt-ingest-manifest'
    buffer = StringIO.new
    if objmanifest
      buffer.puts object_checkm_header
      @metadata[@iconfig.path] ||= metadata_record
    else
      buffer.puts single_file_checkm_header
    end
    CSV.generate(col_sep: '|', row_sep: "\n", force_quotes: false) do |csv|
      files.each do |file|
        if objmanifest
          csv << [
            file_url(file[:key]),
            nil,
            nil,
            file[:size],
            file[:last_modified],
            file[:key],
            nil
                 ]
        else
          @metadata[file[:key]] ||= metadata_record
          csv << [
            file_url(file[:key]),
            nil,
            nil,
            file[:size],
            file[:last_modified],
            file[:key],
            @metadata[file[:key]][:primary_identifier],
            @metadata[file[:key]][:local_identifier],
            @metadata[file[:key]][:creator],
            @metadata[file[:key]][:title],
            @metadata[file[:key]][:date]
                 ]
        end
      end
      buffer.puts csv.string
    end
    save_metadata
    buffer.puts %(#%eof)
    buffer.string
  end

  def object_checkm_preview
    buffer = StringIO.new
    buffer.puts 'Object Checkm'
    buffer.puts "Path: #{@iconfig.path}"
    buffer.puts ''

    descendant_files(@iconfig.path).each do |file|
      buffer.puts "  #{file_url(file[:key])}"
    end
    buffer.string
  end

  def cache_retrieve(key)
    s3_client = Aws::S3::Client.new(
      region: ENV.fetch('AWS_REGION', 'us-west-2')
    )
    obj = s3_client.get_object(
      bucket: @iconfig.cache_bucket,
      key: key
    )
    obj.body.read
  end

  attr_reader :last_updated
end
