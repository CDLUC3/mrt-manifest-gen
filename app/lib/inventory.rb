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
      add(key, size, last_modified, path: path)
    end
  end

  def file_init
    %x[mkdir -p #{File.dirname(@filepath)}]
    CSV.open(@filepath, 'w', col_sep: "\t", row_sep: "\n") do |csv|
      csv << %w[key size last_modified]
    end
  end

  def add(key, size, last_modified, path: '')
    return if key.nil?
    return if key.empty?
    # return unless key.start_with?(path)

    size = 0 if size.nil?
    current_path = path.empty? ? key : key[(path.length + 1)..]
    parent_path = File.dirname(key) == '.' ? '' : File.dirname(key)
    gparent_path = File.dirname(parent_path) == '.' ? '' : File.dirname(parent_path)
    ext = File.extname(key).downcase

    @dirs[parent_path] ||= { count: 0, bytes: 0, files:[], extensions: {}, prefixes: [] }
    @dirs[parent_path][:count] += 1
    @dirs[parent_path][:bytes] += size
    @dirs[parent_path][:extensions][ext] ||= { count: 0, bytes: 0 }
    @dirs[parent_path][:extensions][ext][:count] += 1
    @dirs[parent_path][:extensions][ext][:bytes] += size
    @dirs[parent_path][:files] << { key: current_path, size: size, last_modified: last_modified }

    unless parent_path.empty?
      @dirs[gparent_path][:prefixes] << parent_path unless @dirs[gparent_path][:prefixes].include?(parent_path)
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
    return [] unless @dirs.key?(path) 

    @dirs[path]
  end

  attr_reader :last_updated
end
