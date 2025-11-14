# ROR Data Analysis Tools

A collection of Ruby scripts for working with [Research Organization Registry (ROR)](https://ror.org/) data, including tools to download, process, and query organizational hierarchies and funder mappings.

## Overview

This toolkit provides utilities to:
- Download the latest ROR data from Zenodo
- Build funder-to-ROR ID mappings
- Generate organizational hierarchies (parent/child relationships with full ancestor/descendant chains)
- Query hierarchies and funder mappings efficiently

## Prerequisites

- Ruby 3.0 or later
- `rubyzip` gem (for downloading data)

```bash
gem install rubyzip
```

## Scripts

### 1. `download_ror_data.rb`

Downloads the current ROR data file from Zenodo and extracts schema v2 JSON files.

**Usage:**
```bash
ruby download_ror_data.rb
```

**Features:**
- Automatically fetches the latest ROR data from Zenodo using DOI [10.5281/zenodo.6347574](https://doi.org/10.5281/zenodo.6347574)
  - This DOI represents all versions and always resolves to the latest one
- Follows API redirects to get the current version
- Extracts only `*schema_v2.json` files from the archive
- Overwrites existing files if present

**Output:** Downloads and extracts a file like `v1.XX-YYYY-MM-DD-ror-data_schema_v2.json`

### 2. `build_ror_data.rb`

Builds both funder-to-ROR mapping and organizational hierarchy from ROR data in a single pass.

**Usage:**
```bash
ruby build_ror_data.rb [options]
```

**Options:**
- `--input FILE` - Input ROR data file (auto-detects latest if not specified)
- `--funder-output FILE` - Output funder mapping file (default: `funder_to_ror.json.gz`)
- `--hierarchy-output FILE` - Output hierarchy file (default: `ror_hierarchy.json.gz`)
- `-h, --help` - Show help message

**Features:**
- Automatically finds the most recent ROR data file in the current directory
- Creates funder ID to ROR ID mappings from Fundref external IDs
- Builds complete organizational hierarchies with ancestors and descendants
- Outputs compressed JSON files for efficient storage
- Provides statistics on mappings and hierarchies

**Example:**
```bash
# Use auto-detected latest file
ruby build_ror_data.rb

# Specify custom input file
ruby build_ror_data.rb --input v1.70-2025-08-26-ror-data_schema_v2.json
```

**Outputs:**
- `funder_to_ror.json.gz` - Mapping of funder IDs to ROR IDs
- `ror_hierarchy.json.gz` - Organizational hierarchies with ancestors and descendants

### 3. `ror_hierarchy_lookup.rb`

Efficient lookup tool for querying organizational hierarchies and funder mappings.

**Usage:**
```ruby
require_relative 'ror_hierarchy_lookup'

# Initialize the lookup (loads the gzipped data files)
lookup = RorHierarchyLookup.new

# Look up by ROR ID
result = lookup.lookup('https://ror.org/example123')

# Look up by Funder ID
result = lookup.lookup('100000001')

# Result structure:
# {
#   org_id: "https://ror.org/example123",
#   ancestors: ["https://ror.org/parent1", ...],
#   descendants: ["https://ror.org/child1", ...]
# }
```

**Features:**
- Loads pre-built gzipped hierarchy and funder mapping files
- Supports lookup by both ROR IDs and Funder IDs
- Returns ancestors and descendants for any organization
- Memory-efficient with compressed data

### 4. `funder_to_ror.rb`

Standalone script to create only the funder-to-ROR mapping (legacy, use `build_ror_data.rb` instead).

## Quick Start

1. **Download the latest ROR data:**
   ```bash
   ruby download_ror_data.rb
   ```

2. **Build the mappings and hierarchy:**
   ```bash
   ruby build_ror_data.rb
   ```

3. **Use the lookup in your code:**
   ```ruby
   require_relative 'ror_hierarchy_lookup'
   
   lookup = RorHierarchyLookup.new
   result = lookup.lookup('100000001')  # Funder ID
   puts "Ancestors: #{result[:ancestors]}"
   puts "Descendants: #{result[:descendants]}"
   ```

## Data Files

After running the scripts, you'll have:

- `v*.json` - Raw ROR data file (downloaded from Zenodo)
- `funder_to_ror.json.gz` - Compressed funder-to-ROR mapping
- `ror_hierarchy.json.gz` - Compressed organizational hierarchy data

## Workflow

```
┌─────────────────────────┐
│  download_ror_data.rb   │  Downloads latest ROR data
└───────────┬─────────────┘
            │
            ▼
   v1.XX-YYYY-MM-DD-ror-data_schema_v2.json
            │
            ▼
┌─────────────────────────┐
│   build_ror_data.rb     │  Processes ROR data
└───────────┬─────────────┘
            │
      ┌─────┴──────┐
      ▼            ▼
funder_to_ror  ror_hierarchy
  .json.gz       .json.gz
      │            │
      └─────┬──────┘
            ▼
┌─────────────────────────┐
│ ror_hierarchy_lookup.rb │  Query interface
└─────────────────────────┘
```

## Data Structure

### Funder Mapping
```json
{
  "100000001": "https://ror.org/example123",
  "100000002": "https://ror.org/example456"
}
```

### Hierarchy Data
```json
{
  "https://ror.org/example123": {
    "ancestors": ["https://ror.org/parent1"],
    "descendants": ["https://ror.org/child1", "https://ror.org/child2"]
  }
}
```

## About ROR

The Research Organization Registry (ROR) is a community-led registry of open, sustainable, usable, and unique identifiers for research organizations. Learn more at [ror.org](https://ror.org/).

## ROR Data
ROR data can always be found in Zenodo using the DOI [10.5281/zenodo.6347574](http://doi.org/10.5281/zenodo.6347574). This DOI represents all versions, and will always resolve to the latest one.

## License

This project is independent tooling for working with ROR data. ROR data is licensed under CC0 1.0 Universal.
