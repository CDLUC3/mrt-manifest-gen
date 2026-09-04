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
      csv << %w[key size last_modified]
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
    current_path = path.empty? ? key : key[(path.length + 1)..]
    parent_path = current_path.split('/')[0]
    if current_path == parent_path
      @files << { key: key, size: size, last_modified: last_modified }
    else
      @prefixes << parent_path unless @prefixes.include?(parent_path)
    end
    ext = File.extname(key).downcase
    @count_by_extension[ext] ||= 0
    @bytes_by_extension[ext] ||= 0
    @count_by_extension[ext] += 1
    @bytes_by_extension[ext] += size

    return if filepath.nil?

    CSV.open(filepath, 'a', col_sep: "\t", row_sep: "\n") do |csv|
      csv << [key, size, last_modified]
    end
  end

  def self.format_int(vint)
    vint.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  attr_reader :count, :bytes, :prefixes, :count_by_extension, :bytes_by_extension, :files
end
