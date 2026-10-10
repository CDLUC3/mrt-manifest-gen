# frozen_string_literal: true

require_relative 'cachefile'

## Inventory cache to speed up lambda navigation
class InventoryCSV < CacheFile
  FOLDER = 'inventory'
  FILENAME = 'inventory-file.csv'

  def initialize(iconfig)
    @dirs = {}
    @prefixes = []
    ENV.fetch('CACHE_BUCKET', '')
    key = "#{iconfig.project}/#{FOLDER}/#{FILENAME}"
    localpath = "/tmp/#{FOLDER}/#{FILENAME}"
    super(iconfig, key, localpath)
  end

  def init
    super
    CSV.open(@localpath, 'w', col_sep: "\t", row_sep: "\n") do |csv|
      csv << %w[key size last_modified]
    end
    File.read(@localpath)
  end

  def reset
    @dirs = {}
    @prefixes = []
  end

  def load
    reset
    CSV.parse(read, headers: true, col_sep: "\t", row_sep: "\n") do |row|
      key = row['key']
      size = row['size'].to_i
      last_modified = row['last_modified']
      add(key, size, last_modified)
    end
  end

  def save
    init
    CSV.open(@localpath, 'a', col_sep: "\t", row_sep: "\n") do |csv|
      @dirs.each_value do |dir_info|
        dir_info[:files].each do |file_info|
          csv << [file_info[:key], file_info[:size], file_info[:last_modified]]
        end
      end
    end
    write(File.read(@localpath))
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

  def descendant_extensions(exts, path)
    @dirs[path][:extensions].each do |ext, info|
      exts[ext] ||= { count: 0, bytes: 0, key: ext }
      exts[ext][:count] += info[:count]
      exts[ext][:bytes] += info[:bytes]
    end
    prefixes(path).each do |prefix|
      descendant_extensions(exts, prefix)
    end
    exts
  end

  def extensions(path)
    exts = {}
    descendant_extensions(exts, path)
    topexts = {}
    exts.values
      .sort_by { |ext| ext.fetch(:count, 0) }
      .reverse
      .each do |ext|
        topexts[ext[:key]] = ext
        break if topexts.length >= InventoryConfig::MAX_EXTENSIONS
      end
    topexts
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

  def object_checkm_preview
    buffer = StringIO.new
    buffer.puts 'Object Checkm'
    buffer.puts "Path: #{iconfig.path}"
    buffer.puts ''

    descendant_files(iconfig.path).each do |file|
      buffer.puts "  #{file_url(file[:key])}"
    end
    buffer.string
  end

  def checkm_preview(depth = '')
    return object_checkm_preview if depth.empty?

    buffer = StringIO.new
    buffer.puts 'Manifest Checkm'
    buffer.puts "Path: #{iconfig.path}"
    buffer.puts "Depth: #{depth}"
    buffer.puts ''

    descendant_files_by_depth(iconfig.path, depth.to_i).each do |mapkey, files|
      buffer.puts manifest_url(mapkey)
      files.each do |file|
        buffer.puts "  #{file_url(file[:key])}"
      end
    end
    buffer.string
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
    @dirs[parent_path][:extensions][ext] ||= { count: 0, bytes: 0, key: ext }
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
end
