# frozen_string_literal: true

require "json"
require "set"
require "optparse"

class RorToCountriesBuilder
  DEFAULT_DATA_DIR = "data_files"
  DEFAULT_OUTPUT_PATH = "ror_to_countries.json"
  INPUT_GLOBS = [
    "**/*ror-data.json",   # ROR v2 extracted JSON
    "**/*schema_v2.json",  # legacy extracted JSON
  ].freeze

  def initialize(data_dir:, input_path:, output_path:)
    @data_dir = data_dir
    @input_path = input_path
    @output_path = output_path
  end

  def run
    input = resolved_input_path
    mapping = build_mapping(input)
    write_json(@output_path, mapping)

    puts "Input:  #{input}"
    puts "Output: #{@output_path}"
    puts "ROR IDs written: #{mapping.length}"
  end

  private

  def resolved_input_path
    return validate_input_path!(@input_path) if @input_path

    auto = find_latest_extracted_ror_json(@data_dir)
    raise missing_input_error(@data_dir) unless auto

    auto
  end

  def validate_input_path!(path)
    raise "Input file not found: #{path}" unless File.exist?(path)
    path
  end

  def find_latest_extracted_ror_json(data_dir)
    candidates = INPUT_GLOBS.flat_map { |glob| Dir.glob(File.join(data_dir, glob)) }.uniq
    return nil if candidates.empty?

    candidates.max_by { |path| File.mtime(path) }
  end

  def missing_input_error(data_dir)
    <<~MSG
      Could not find an extracted ROR JSON file under #{data_dir}/
      Looked for:
        - #{File.join(data_dir, "**/*ror-data.json")}
        - #{File.join(data_dir, "**/*schema_v2.json")}

      Run:
        ruby download_ror_data.rb

      Or pass:
        ruby build_ror_to_countries.rb --input path/to/extracted_ror-data.json
    MSG
  end

  def build_mapping(input_path)
    records = parse_json_array(input_path)

    records.each_with_object({}) do |record, map|
      ror_id = record.fetch("id", "").to_s.strip
      next if ror_id.empty?

      map[ror_id] = extract_country_codes(record)
    end
  end

  def parse_json_array(path)
    data = JSON.parse(File.read(path))
    return data if data.is_a?(Array)

    raise "Expected JSON array of ROR records in #{path}, got #{data.class}"
  end

  def extract_country_codes(record)
    codes =
      Array(record["locations"]).filter_map do |loc|
        loc.dig("geonames_details", "country_code")&.to_s&.strip
      end

    # Normalize: uppercase + dedupe + stable ordering
    Set.new(codes.reject(&:empty?).map(&:upcase)).to_a.sort
  end

  def write_json(path, obj)
    File.write(path, JSON.pretty_generate(obj))
  end
end

options = {
  data_dir: RorToCountriesBuilder::DEFAULT_DATA_DIR,
  input_path: nil,
  output_path: RorToCountriesBuilder::DEFAULT_OUTPUT_PATH,
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby build_ror_to_countries.rb [options]"

  opts.on("--data-dir DIR", "Directory with extracted ROR JSON (default: #{options[:data_dir]}/)") do |dir|
    options[:data_dir] = dir
  end

  opts.on("--input FILE", "Explicit path to extracted ROR JSON (overrides auto-detect)") do |file|
    options[:input_path] = file
  end

  opts.on("--output FILE", "Output mapping file (default: #{options[:output_path]})") do |file|
    options[:output_path] = file
  end

  opts.on("-h", "--help", "Show help") do
    puts opts
    exit
  end
end.parse!

RorToCountriesBuilder
  .new(
    data_dir: options[:data_dir],
    input_path: options[:input_path],
    output_path: options[:output_path],
  )
  .run