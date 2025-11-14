#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'zlib'
require 'optparse'
require 'set'

# Build ancestor and descendant hierarchies from ROR data.
#
# This script reads a ROR data JSON file and creates a dictionary mapping
# each organization ID to lists of its ancestors (via parent relationships)
# and descendants (via child relationships).

# Load ROR data from JSON file
def load_ror_data(filepath)
  puts "Loading data from #{filepath}..."
  JSON.parse(File.read(filepath))
end

# Build maps of parent and child relationships
#
# Returns:
#   [parent_map, child_map, id_to_label]
#     - parent_map: {org_id => [list of parent IDs]}
#     - child_map: {org_id => [list of child IDs]}
#     - id_to_label: {org_id => organization name}
def build_relationship_maps(data)
  parent_map = {}
  child_map = {}
  id_to_label = {}
  
  data.each do |entry|
    org_id = entry['id']
    next unless org_id
    
    # Get organization name from names array
    names = entry['names'] || []
    id_to_label[org_id] = if names.length > 0
                            names[0]['value'] || 'Unknown'
                          else
                            'Unknown'
                          end
    
    # Initialize lists
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
  end
  
  [parent_map, child_map, id_to_label]
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
    
    # Get parents of current org
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
    
    # Get children of current org
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
# Uses memoization to avoid recomputing ancestors/descendants for the same organization
def build_hierarchy(data)
  parent_map, child_map, id_to_label = build_relationship_maps(data)
  
  # Collect all unique organization IDs (both from entries and referenced in relationships)
  all_org_ids = Set.new(parent_map.keys)
  all_org_ids.merge(child_map.keys)
  
  # Also add any IDs that are referenced in relationships but might not have entries
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

# Main
if __FILE__ == $PROGRAM_NAME
  options = {
    input: nil,
    output: 'ror_hierarchy.json.gz'
  }
  
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby build_hierarchy.rb <input_file> [options]"
    opts.banner += "\nExample: ruby build_hierarchy.rb v1.70-2025-08-26-ror-data_schema_v2.json"
    opts.banner += "\n         ruby build_hierarchy.rb v1.70-2025-08-26-ror-data_schema_v2.json --output custom_output.json.gz"
    
    opts.on('--output FILE', 'Output gzipped JSON file (default: ror_hierarchy.json.gz)') do |file|
      options[:output] = file
    end
    
    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      exit
    end
  end.parse!
  
  if ARGV.empty?
    puts "Usage: ruby build_hierarchy.rb <input_file> [options]"
    puts "Example: ruby build_hierarchy.rb v1.70-2025-08-26-ror-data_schema_v2.json"
    puts "         ruby build_hierarchy.rb v1.70-2025-08-26-ror-data_schema_v2.json --output custom_output.json.gz"
    exit 1
  end
  
  options[:input] = ARGV[0]
  
  # Load data
  data = load_ror_data(options[:input])
  puts "Loaded #{data.length} organizations"
  
  # Build hierarchy
  puts "Building hierarchy..."
  hierarchy = build_hierarchy(data)
  
  # Calculate statistics
  total_orgs = hierarchy.size
  orgs_with_ancestors = hierarchy.values.count { |v| !v['ancestors'].empty? }
  orgs_with_descendants = hierarchy.values.count { |v| !v['descendants'].empty? }
  orgs_with_both = hierarchy.values.count { |v| !v['ancestors'].empty? && !v['descendants'].empty? }
  
  puts "\nStatistics:"
  puts "  Total organizations: #{total_orgs}"
  puts "  Organizations with ancestors: #{orgs_with_ancestors}"
  puts "  Organizations with descendants: #{orgs_with_descendants}"
  puts "  Organizations with both ancestors and descendants: #{orgs_with_both}"
  
  # Write gzipped JSON output
  puts "\nWriting gzipped results to #{options[:output]}..."
  Zlib::GzipWriter.open(options[:output]) do |gz|
    gz.write(JSON.generate(hierarchy))
  end
  
  puts "Done! Created: #{options[:output]}"
  
  # Show file size
  size_mb = File.size(options[:output]) / (1024.0 * 1024.0)
  puts "File size: #{size_mb.round(2)} MB"
end
