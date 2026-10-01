# frozen_string_literal: true

require 'aws-sdk-s3'
require 'csv'
require 'net/http'
require 'uri'

## Track inventory statistics for the portion of the inventory being analyzed
class Inventory
  def initialize(iconfig)
    @filepath = InventoryConfig::INVENTORY_FILE
    @iconfig = iconfig
    @last_updated = nil
    reset
  end

  def reset
    @dirs = {}
    @prefixes = []
  end

  def get_csv
    if @iconfig.cache_bucket.empty?
      file_init unless File.exist?(@filepath)
      @last_updated = File.mtime(@filepath)
      File.read(@filepath)
    else
      begin
        s3_client = Aws::S3::Client.new(
          region: ENV.fetch('AWS_REGION', 'us-west-2')
        )
        obj = s3_client.get_object(
          bucket: @iconfig.cache_bucket,
          key: "#{@iconfig.project}/inventory/inventory-file.csv"
        )
        @last_updated = obj.last_modified
        obj.body.read
      rescue Aws::S3::Errors::NoSuchKey
        file_init
        @last_updated = File.mtime(@filepath)
        File.read(@filepath)
      end
    end
  end

  def load_csv(path: '')
    reset
    CSV.parse(get_csv, headers: true, col_sep: "\t", row_sep: "\n") do |row|
      key = row['key']
      size = row['size'].to_i
      last_modified = row['last_modified']
      add(key, size, last_modified)
    end
  end

  def file_init
    %x[mkdir -p #{File.dirname(@filepath)}]
    CSV.open(@filepath, 'w', col_sep: "\t", row_sep: "\n") do |csv|
      csv << %w[key size last_modified]
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

    @dirs[parent_path] ||= { count: 0, bytes: 0, files:[], extensions: {}, prefixes: [] }
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
    if gparent_path != ppath
      @dirs[gparent_path] ||= { count: 0, bytes: 0, files:[], extensions: {}, prefixes: [] }
      @dirs[gparent_path][:prefixes] << ppath unless @dirs[gparent_path][:prefixes].include?(ppath)
      add_prefix(gparent_path)
    end
  end

  def save
    file_init
    CSV.open(@filepath, 'a', col_sep: "\t", row_sep: "\n") do |csv|
      @dirs.each do |path, dir_info|
        dir_info[:files].each do |file_info|
          csv << [file_info[:key], file_info[:size], file_info[:last_modified]]
        end
      end
    end
    unless @iconfig.cache_bucket.empty?
      s3_client = Aws::S3::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-west-2')
      )
      s3_client.put_object(
        bucket: @iconfig.cache_bucket,
        key: "#{@iconfig.project}/inventory/inventory-file.csv",
        body: File.read(@filepath)
      )
    end
    @last_updated = File.mtime(@filepath)
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

attr_reader :last_updated
end
