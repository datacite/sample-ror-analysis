#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'zlib'
require 'optparse'
require 'set'

begin
  require 'yajl'
  STREAMING_PARSER_AVAILABLE = true
rescue LoadError
  STREAMING_PARSER_AVAILABLE = false
end

# Build both funder-to-ROR mapping AND hierarchy from ROR data in a single pass
#
# This script reads the ROR data JSON file once and creates:
# 1. Funder ID to ROR ID mapping (from fundref external IDs)
# 2. Organization hierarchy with ancestors and descendants (from parent/child relationships)

# Load ROR data from JSON file using streaming parser if available
def load_ror_data(filepath)
  puts "Loading data from #{filepath}..."
  
  if STREAMING_PARSER_AVAILABLE
    puts "Using streaming JSON parser for better memory efficiency..."
    parser = Yajl::Parser.new
    File.open(filepath, 'r') do |file|
      parser.parse(file)
    end
  else
    JSON.parse(File.read(filepath))
  end
end

# Build relationship maps from data
#
# Returns:
#   [parent_map, child_map]
def build_relationship_maps(data)
  parent_map = {}
  child_map = {}
  
  data.each do |entry|
    org_id = entry['id']
    next unless org_id
    
    # Parse relationships
    relationships = entry['relationships'] || []
    next if relationships.empty?
    
    parents = []
    children = []
    
    relationships.each do |rel|
      rel_type = (rel['type'] || '').downcase
      rel_id = rel['id']
      
      if rel_type == 'parent' && rel_id
        parents << rel_id
      elsif rel_type == 'child' && rel_id
        children << rel_id
      end
    end
    
    # Only add to maps if there are actual relationships
    parent_map[org_id] = parents unless parents.empty?
    child_map[org_id] = children unless children.empty?
  end
  
  [parent_map, child_map]
end

# Build funder mapping from data
#
# Returns:
#   funder_to_ror hash
def build_funder_mapping(data)
  funder_to_ror = {}
  
  data.each do |entry|
    org_id = entry['id']
    next unless org_id
    
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
  
  funder_to_ror
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
    
    # Only include organizations that have at least one ancestor or descendant
    if !ancestors.empty? || !descendants.empty?
      hierarchy[org_id] = {
        'ancestors' => ancestors,
        'descendants' => descendants
      }
    end
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
    hierarchy_output: 'ror_hierarchy.json.gz',
    build_funder: true,
    build_hierarchy: true
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
    
    opts.on('--funder-only', 'Build only the funder mapping (not hierarchy)') do
      options[:build_funder] = true
      options[:build_hierarchy] = false
    end
    
    opts.on('--hierarchy-only', 'Build only the hierarchy (not funder mapping)') do
      options[:build_funder] = false
      options[:build_hierarchy] = true
    end
    
    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      puts "\nThis script creates both:"
      puts "  1. Funder ID to ROR ID mapping"
      puts "  2. Organization hierarchy (ancestors/descendants)"
      puts "\nFrom a single pass through the ROR data file."
      puts "\nUse --funder-only or --hierarchy-only to build just one output."
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
  
  # Build maps based on what's requested
  parent_map = nil
  child_map = nil
  funder_to_ror = nil
  
  if options[:build_hierarchy]
    puts "\nBuilding relationship maps..."
    parent_map, child_map = build_relationship_maps(data)
  end
  
  if options[:build_funder]
    puts "\nBuilding funder mapping..."
    funder_to_ror = build_funder_mapping(data)
  end
  
  # Build hierarchy if requested
  hierarchy = nil
  if options[:build_hierarchy]
    puts "Building hierarchy..."
    hierarchy = build_hierarchy(parent_map, child_map)
  end
  
  # Statistics
  if options[:build_funder]
    puts "\n=== Funder Mapping Statistics ==="
    puts "  Total funder-to-ROR mappings: #{funder_to_ror.size}"
  end
  
  if options[:build_hierarchy]
    puts "\n=== Hierarchy Statistics ==="
    total_orgs = hierarchy.size
    orgs_with_ancestors = hierarchy.values.count { |v| !v['ancestors'].empty? }
    orgs_with_descendants = hierarchy.values.count { |v| !v['descendants'].empty? }
    orgs_with_both = hierarchy.values.count { |v| !v['ancestors'].empty? && !v['descendants'].empty? }
    
    puts "  Total organizations: #{total_orgs}"
    puts "  Organizations with ancestors: #{orgs_with_ancestors}"
    puts "  Organizations with descendants: #{orgs_with_descendants}"
    puts "  Organizations with both: #{orgs_with_both}"
  end
  
  # Write outputs
  puts "\n=== Writing Output Files ==="
  write_gzipped_json(funder_to_ror, options[:funder_output]) if options[:build_funder]
  write_gzipped_json(hierarchy, options[:hierarchy_output]) if options[:build_hierarchy]
  
  puts "\nDone!"
end
