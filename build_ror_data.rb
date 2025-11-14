#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'zlib'
require 'optparse'
require 'set'

# Build both funder-to-ROR mapping AND hierarchy from ROR data in a single pass
#
# This script reads the ROR data JSON file once and creates:
# 1. Funder ID to ROR ID mapping (from fundref external IDs)
# 2. Organization hierarchy with ancestors and descendants (from parent/child relationships)

# Load ROR data from JSON file
def load_ror_data(filepath)
  puts "Loading data from #{filepath}..."
  JSON.parse(File.read(filepath))
end

# Build relationship maps AND funder mapping from data in a single pass
#
# Returns:
#   [parent_map, child_map, funder_to_ror]
def build_maps(data)
  parent_map = {}
  child_map = {}
  funder_to_ror = {}
  
  data.each do |entry|
    org_id = entry['id']
    next unless org_id
    
    # Initialize relationship lists
    parent_map[org_id] = []
    child_map[org_id] = []
    
    # Parse relationships
    relationships = entry['relationships'] || []
    relationships.each do |rel|
      rel_type = (rel['type'] || '').downcase
      rel_id = rel['id']
      
      if rel_type == 'parent' && rel_id
        parent_map[org_id] << rel_id
      elsif rel_type == 'child' && rel_id
        child_map[org_id] << rel_id
      end
    end
    
    # Parse funder IDs (fundref external IDs)
    external_ids = entry['external_ids'] || []
    external_ids.each do |external_id|
      next unless external_id['type'] == 'fundref'
      
      funder_ids = external_id['all'] || []
      funder_ids << external_id['preferred'] if external_id['preferred']
      funder_ids.uniq!
      
      funder_ids.each do |funder_id|
        funder_to_ror[funder_id] = org_id
      end
    end
  end
  
  [parent_map, child_map, funder_to_ror]
end

# Find all ancestors by traversing parent relationships
def find_ancestors(org_id, parent_map)
  ancestors = []
  visited = Set.new
  queue = [org_id]
  
  until queue.empty?
    current_id = queue.shift
    next if visited.include?(current_id)
    
    visited.add(current_id)
    
    parents = parent_map[current_id] || []
    parents.each do |parent_id|
      if !visited.include?(parent_id) && parent_id != org_id
        ancestors << parent_id
        queue << parent_id
      end
    end
  end
  
  ancestors
end

# Find all descendants by traversing child relationships
def find_descendants(org_id, child_map)
  descendants = []
  visited = Set.new
  queue = [org_id]
  
  until queue.empty?
    current_id = queue.shift
    next if visited.include?(current_id)
    
    visited.add(current_id)
    
    children = child_map[current_id] || []
    children.each do |child_id|
      if !visited.include?(child_id) && child_id != org_id
        descendants << child_id
        queue << child_id
      end
    end
  end
  
  descendants
end

# Build complete hierarchy with ancestors and descendants for each organization
def build_hierarchy(parent_map, child_map)
  # Collect all unique organization IDs
  all_org_ids = Set.new(parent_map.keys)
  all_org_ids.merge(child_map.keys)
  
  # Add any IDs that are referenced in relationships but might not have entries
  parent_map.values.each { |parents| all_org_ids.merge(parents) }
  child_map.values.each { |children| all_org_ids.merge(children) }
  
  # Caches to store computed results
  ancestor_cache = {}
  descendant_cache = {}
  
  get_ancestors_cached = lambda do |org_id|
    ancestor_cache[org_id] ||= find_ancestors(org_id, parent_map)
  end
  
  get_descendants_cached = lambda do |org_id|
    descendant_cache[org_id] ||= find_descendants(org_id, child_map)
  end
  
  hierarchy = {}
  
  all_org_ids.each do |org_id|
    ancestors = get_ancestors_cached.call(org_id)
    descendants = get_descendants_cached.call(org_id)
    
    hierarchy[org_id] = {
      'ancestors' => ancestors,
      'descendants' => descendants
    }
  end
  
  hierarchy
end

# Write gzipped JSON file
def write_gzipped_json(data, output_file)
  Zlib::GzipWriter.open(output_file) do |gz|
    gz.write(JSON.generate(data))
  end
  
  size_kb = File.size(output_file) / 1024.0
  size_mb = size_kb / 1024.0
  
  if size_mb >= 1.0
    puts "  File: #{output_file} (#{size_mb.round(2)} MB)"
  else
    puts "  File: #{output_file} (#{size_kb.round(2)} KB)"
  end
end

# Find the most recent ROR data file in the current directory
def find_latest_ror_file
  files = Dir.glob('v*schema_v2.json')
  return nil if files.empty?
  
  # Sort by filename (version numbers) and take the last one
  files.sort.last
end

# Main
if __FILE__ == $PROGRAM_NAME
  default_input = find_latest_ror_file
  
  unless default_input
    puts "No ROR data file found in the current directory."
    puts "Please download the ROR data file first by running:"
    puts "  ruby download_ror_data.rb"
    exit 1
  end
  
  options = {
    input: default_input,
    funder_output: 'funder_to_ror.json.gz',
    hierarchy_output: 'ror_hierarchy.json.gz'
  }
  
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby build_ror_data.rb [options]"
    
    opts.on('--input FILE', "Input ROR data file (default: #{default_input})") do |file|
      options[:input] = file
    end
    
    opts.on('--funder-output FILE', 'Output funder mapping file (default: funder_to_ror.json.gz)') do |file|
      options[:funder_output] = file
    end
    
    opts.on('--hierarchy-output FILE', 'Output hierarchy file (default: ror_hierarchy.json.gz)') do |file|
      options[:hierarchy_output] = file
    end
    
    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      puts "\nThis script creates both:"
      puts "  1. Funder ID to ROR ID mapping"
      puts "  2. Organization hierarchy (ancestors/descendants)"
      puts "\nFrom a single pass through the ROR data file."
      exit
    end
  end.parse!
  
  # Verify input file exists
  unless File.exist?(options[:input])
    puts "Error: Input file '#{options[:input]}' not found."
    puts "Please download the ROR data file first by running:"
    puts "  ruby download_ror_data.rb"
    exit 1
  end
  
  # Load data (expensive operation - done once)
  data = load_ror_data(options[:input])
  puts "Loaded #{data.length} organizations"
  
  # Build all maps in a single pass
  puts "\nBuilding maps..."
  parent_map, child_map, funder_to_ror = build_maps(data)
  
  # Build hierarchy
  puts "Building hierarchy..."
  hierarchy = build_hierarchy(parent_map, child_map)
  
  # Statistics
  puts "\n=== Funder Mapping Statistics ==="
  puts "  Total funder-to-ROR mappings: #{funder_to_ror.size}"
  
  puts "\n=== Hierarchy Statistics ==="
  total_orgs = hierarchy.size
  orgs_with_ancestors = hierarchy.values.count { |v| !v['ancestors'].empty? }
  orgs_with_descendants = hierarchy.values.count { |v| !v['descendants'].empty? }
  orgs_with_both = hierarchy.values.count { |v| !v['ancestors'].empty? && !v['descendants'].empty? }
  
  puts "  Total organizations: #{total_orgs}"
  puts "  Organizations with ancestors: #{orgs_with_ancestors}"
  puts "  Organizations with descendants: #{orgs_with_descendants}"
  puts "  Organizations with both: #{orgs_with_both}"
  
  # Write outputs
  puts "\n=== Writing Output Files ==="
  write_gzipped_json(funder_to_ror, options[:funder_output])
  write_gzipped_json(hierarchy, options[:hierarchy_output])
  
  puts "\nDone!"
end
