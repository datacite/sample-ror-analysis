#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'zlib'

# ROR Hierarchy Lookup
# Provides efficient lookup of ancestors and descendants from gzipped JSON
# Supports both ROR IDs and Funder IDs (looks up ROR ID via funder mapping)
class RorHierarchyLookup
  def initialize(hierarchy_file = 'ror_hierarchy.json.gz', funder_mapping_file = 'funder_to_ror.json.gz')
    @hierarchy_data = load_data(hierarchy_file)
    @funder_to_ror = load_data(funder_mapping_file)
  end

  private

  def load_data(file_path)
    if file_path.end_with?('.gz')
      # Gzipped JSON
      Zlib::GzipReader.open(file_path) { |gz| JSON.parse(gz.read) }
    else
      # Regular JSON
      JSON.parse(File.read(file_path))
    end
  end
  
  # Convert a funder ID or ROR ID to a ROR ID
  def resolve_to_ror_id(id)
    # If it looks like a ROR ID (starts with https://ror.org/), use it directly
    if id.start_with?('https://ror.org/')
      return id
    end
    
    # Otherwise, try to look it up as a funder ID
    ror_id = @funder_to_ror[id]
    return ror_id if ror_id
    
    # If not found, return nil
    nil
  end

  public

  # Get ancestors and descendants for a given organization ID (ROR ID or Funder ID)
  # @param id [String] The ROR organization ID or Funder ID
  # @return [Hash] Hash with :org_id, :ancestors and :descendants arrays, or nil if not found
  def lookup(id)
    # Resolve to ROR ID
    ror_id = resolve_to_ror_id(id)
    return nil unless ror_id
    
    data = @hierarchy_data[ror_id]
    return nil unless data

    {
      org_id: ror_id,
      input_id: id,
      ancestors: data['ancestors'],
      descendants: data['descendants']
    }
  end

  # Get only ancestors for an organization
  # @param id [String] The ROR organization ID or Funder ID
  # @return [Array] Array of ancestor IDs, or nil if not found
  def ancestors(id)
    result = lookup(id)
    result ? result[:ancestors] : nil
  end

  # Get only descendants for an organization
  # @param id [String] The ROR organization ID or Funder ID
  # @return [Array] Array of descendant IDs, or nil if not found
  def descendants(id)
    result = lookup(id)
    result ? result[:descendants] : nil
  end

  # Check if an organization has any ancestors
  # @param id [String] The ROR organization ID or Funder ID
  # @return [Boolean]
  def has_ancestors?(id)
    ancestors = self.ancestors(id)
    ancestors && !ancestors.empty?
  end

  # Check if an organization has any descendants
  # @param id [String] The ROR organization ID or Funder ID
  # @return [Boolean]
  def has_descendants?(id)
    descendants = self.descendants(id)
    descendants && !descendants.empty?
  end
end

# Example usage
if __FILE__ == $PROGRAM_NAME
  if ARGV.length < 1
    puts "Usage: ruby ror_hierarchy_lookup.rb <id> [hierarchy_file] [funder_mapping_file]"
    puts "  <id> can be either a ROR ID or a Funder ID"
    puts ""
    puts "Examples:"
    puts "  ruby ror_hierarchy_lookup.rb https://ror.org/012xzy7a9"
    puts "  ruby ror_hierarchy_lookup.rb 100000001"
    puts "  ruby ror_hierarchy_lookup.rb https://ror.org/012xzy7a9 ror_hierarchy.json.gz funder_to_ror.json.gz"
    exit 1
  end

  id = ARGV[0]
  hierarchy_file = ARGV[1] || 'ror_hierarchy.json.gz'
  funder_mapping_file = ARGV[2] || 'funder_to_ror.json.gz'

  lookup = RorHierarchyLookup.new(hierarchy_file, funder_mapping_file)

  result = lookup.lookup(id)

  if result
    if result[:input_id] != result[:org_id]
      puts "Funder ID: #{result[:input_id]}"
      puts "Resolved to ROR ID: #{result[:org_id]}"
    else
      puts "ROR ID: #{result[:org_id]}"
    end
    puts "\nAncestors (#{result[:ancestors].length}):"
    result[:ancestors].each { |id| puts "  - #{id}" }
    puts "\nDescendants (#{result[:descendants].length}):"
    result[:descendants].each { |id| puts "  - #{id}" }
  else
    puts "Organization not found: #{id}"
    puts "(Tried as both ROR ID and Funder ID)"
  end
end
