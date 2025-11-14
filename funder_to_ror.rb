#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'zlib'
require 'optparse'

# Create funder ID to ROR ID mapping from ROR data file
def create_funder_to_ror_mapping(ror_data_file)
  mapping = {}
  
  puts "Reading ROR data from: #{ror_data_file}"
  ror_data_list = JSON.parse(File.read(ror_data_file))
  
  ror_data_list.each do |ror_data|
    ror_id = ror_data['id']
    next unless ror_id
    
    external_ids = ror_data['external_ids'] || []
    external_ids.each do |external_id|
      next unless external_id['type'] == 'fundref'
      
      funder_ids = external_id['all'] || []
      funder_ids << external_id['preferred'] if external_id['preferred']
      funder_ids.uniq!
      
      funder_ids.each do |funder_id|
        mapping[funder_id] = ror_id
      end
    end
  end
  
  mapping
end

# Write mapping to gzipped JSON file
def write_to_gzipped_json(mapping, output_file)
  puts "Writing #{mapping.size} mappings to gzipped JSON..."
  
  Zlib::GzipWriter.open(output_file) do |gz|
    gz.write(JSON.generate(mapping))
  end
  
  # Show file size
  size_kb = File.size(output_file) / 1024.0
  puts "Gzipped JSON output written to: #{output_file}"
  puts "File size: #{size_kb.round(2)} KB"
end

# Main
if __FILE__ == $PROGRAM_NAME
  options = {
    input: 'v1.70-2025-08-26-ror-data_schema_v2.json',
    output: 'funder_to_ror.json.gz'
  }
  
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby funder_to_ror.rb [options]"
    
    opts.on('--input FILE', 'Input ROR data file (default: v1.70-2025-08-26-ror-data_schema_v2.json)') do |file|
      options[:input] = file
    end
    
    opts.on('--output FILE', 'Output gzipped JSON file (default: funder_to_ror.json.gz)') do |file|
      options[:output] = file
    end
    
    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      exit
    end
  end.parse!
  
  # Create the mapping
  mapping = create_funder_to_ror_mapping(options[:input])
  puts "Created #{mapping.size} funder-to-ROR mappings"
  
  # Write gzipped JSON output
  write_to_gzipped_json(mapping, options[:output])
  
  puts "Done!"
end
