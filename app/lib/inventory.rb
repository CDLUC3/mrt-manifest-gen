# frozen_string_literal: true

require 'aws-sdk-s3'
require 'csv'
require 'net/http'
require 'uri'

## Track inventory statistics for the portion of the inventory being analyzed
class Inventory
  def initialize
    reset
  end

  def reset
    @dirs = {}
    @prefixes = []
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
    %x[mkdir -p /tmp/inventory]
    CSV.open(filepath, 'w', col_sep: "\t", row_sep: "\n") do |csv|
      csv << %w[key size last_modified]
    end
    filepath
  end

  def add(key, size, last_modified, path: '', filepath: nil)
    return if key.nil?
    return if key.empty?
    # return unless key.start_with?(path)

    size = 0 if size.nil?
    current_path = path.empty? ? key : key[(path.length + 1)..]
    parent_path = File.dirname(key) == '.' ? '' : File.dirname(key)
    gparent_path = File.dirname(parent_path) == '.' ? '' : File.dirname(parent_path)
    ext = File.extname(key).downcase

    puts "#{key}, #{parent_path}, #{gparent_path}"


    @dirs[parent_path] ||= { count: 0, bytes: 0, files:[], extensions: {}, prefixes: [] }
    @dirs[parent_path][:count] += 1
    @dirs[parent_path][:bytes] += size
    @dirs[parent_path][:extensions][ext] ||= { count: 0, bytes: 0 }
    @dirs[parent_path][:extensions][ext][:count] += 1
    @dirs[parent_path][:extensions][ext][:bytes] += size
    if path == parent_path
      @dirs[parent_path][:files] << { key: current_path, size: size, last_modified: last_modified }
    end

    unless parent_path.empty?
      @dirs[gparent_path][:prefixes] << parent_path unless @dirs[gparent_path][:prefixes].include?(parent_path)
    end

    return if filepath.nil?

    file_init(filepath) unless File.exist?(filepath)
    CSV.open(filepath, 'a', col_sep: "\t", row_sep: "\n") do |csv|
      csv << [key, size, last_modified]
    end
  end

  def write_to_csv(filepath)
    file_init(filepath)
    CSV.open(filepath, 'a', col_sep: "\t", row_sep: "\n") do |csv|
      @files.each do |key, file_info|
        csv << [file_info[:key], file_info[:size], file_info[:last_modified]]
      end
    end
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

  attr_reader :dirs
end
