require 'aws-sdk-s3'
require 'csv'
require 'open-uri'

class Inventory
  def initialize
    reset
  end

  def reset
    @count = 0
    @bytes = 0
    @prefixes = []
    @files = []
    @count_by_extension = {}
    @bytes_by_extension = {}
  end

  def load_from_csv(file_path, path: '')
    reset
    CSV.parse(File.read(file_path), headers: true, col_sep: "\t", row_sep: "\n") do |row|
      key = row['key']
      size = row['size'].to_i
      last_modified = row['last_modified']
      add(key, size, last_modified, path: path)
    end
  end

  def file_init(filepath)
    CSV.open(filepath, 'w', col_sep: "\t", row_sep: "\n") do |csv|
      csv << ['key', 'size', 'last_modified']
    end
    filepath
  end

  def add(key, size, last_modified, path: '', filepath: nil)
    return if key.nil?
    return if key.empty?
    return unless key.start_with?(path)
    size = 0 if size.nil?
    @count += 1
    @bytes += size
    current_path = path.empty? ? key : key[path.length+1..-1]
    parent_path = current_path.split('/')[0]
    if current_path == parent_path
      @files << {key: key, size: size, last_modified: last_modified}
    else
      unless @prefixes.include?(parent_path)
        @prefixes << parent_path
      end
    end
    ext = File.extname(key).downcase
    @count_by_extension[ext] ||= 0
    @bytes_by_extension[ext] ||= 0
    @count_by_extension[ext] += 1
    @bytes_by_extension[ext] += size

    unless filepath.nil?
      CSV.open(filepath, 'a', col_sep: "\t", row_sep: "\n") do |csv|
        csv << [key, size, last_modified]
      end
    end
  end

  def self.format_int(vint)
    vint.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  attr_reader :count, :bytes, :prefixes, :count_by_extension, :bytes_by_extension, :files
end

class InventoryConfig
  INVENTORY_FILE = '/app/inventory-file.csv'

  def initialize(path: '')
    @path = path
    # Allowed values: s3api, httpsapi, inventoryfile, inventoryurl
    @mode = ENV.fetch('MANIFEST_MODE', 's3api')
    @prefix = ENV.fetch('MANIFEST_PREFIX', '')
    @source = ''

    @inventory = Inventory.new
    if File.exist?(INVENTORY_FILE)
      begin
        @inventory.load_from_csv(INVENTORY_FILE, path: path)
      rescue
      end
    end

    case @mode
      when 's3api'
        bucket = ENV.fetch('MANIFEST_BUCKET', '')
        @source = "s3://#{bucket}/#{@prefix}"
        s3_reload(bucket, @prefix, path: path) if reload_needed
      when 'inventoryfile'
        @file = ENV.fetch('MANIFEST_FILE', '')
        @source = "file://app/inventory-file.csv"
      when 'inventoryurl'
        @url = ENV.fetch('MANIFEST_URL', '')
        @source = @url
        url_reload(@url, path: path) if reload_needed
      when 'httpsapi'
        @source = ENV.fetch('MANIFEST_URL', '')
    end
  end

  def url_reload(url, path: '')
    File(INVENTORY_FILE, 'w') do |file|
      file.write(URI.open(url).read)
    end
    @inventory.load_from_csv(INVENTORY_FILE, path: path)
  end

  def s3_reload(bucket, prefix, path: '')
    s3_client = Aws::S3::Client.new(
      region: ENV.fetch('AWS_REGION', 'us-west-2')
    )
    @inventory.file_init(INVENTORY_FILE)
    continuation_token = nil
    loop do
      response = s3_client.list_objects_v2(
        bucket: bucket,
        prefix: prefix,
        continuation_token: continuation_token
      )
      response.contents.each do |object|
        @inventory.add(object.key, object.size, object.last_modified,filepath: INVENTORY_FILE)
      end
      break unless response.is_truncated

      continuation_token = response.next_continuation_token
    end
    
  end

  def last_updated
    if File.exist?(INVENTORY_FILE)
      File.mtime(INVENTORY_FILE)
    else
      nil
    end
  end

  def reload_needed
    return true if last_updated.nil?
    return true if @inventory.count == 0

    last_updated < (Time.now - 180) # Reload if older than 3 minutes
  end

  def prefix_path(folder)
    @path.empty? ? "/#{folder}" : "/#{@path}/#{File.basename(folder)}"
  end

  def parent_path
    return '/' if @path.empty?
    parent = File.dirname(@path)
    return '/' if parent == '.'
    "/#{parent}"
  end

  def parent_name
    @path.empty? ? '/' : '..'
  end

  attr_reader :mode, :prefix, :reload, :source, :file, :url, :inventory, :path
end
