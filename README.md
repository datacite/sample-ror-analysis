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
- Bundler for dependency management

## Installation

1. Clone this repository
2. Install dependencies:
   ```bash
   bundle install
   ```

## Directory Structure

By default, files are organized into two directories:
- **`data_files/`** - Contains downloaded raw data files (zip files and extracted JSON schema files)
- **`output/`** - Contains generated/processed files (funder_to_ror.json, ror_hierarchy.json)

Both directories are created automatically if they don't exist. You can customize these locations using command-line options.

## Scripts

### 1. `download_ror_data.rb`

Downloads the current ROR data file from Zenodo and extracts the appropriate schema JSON files based on the data format version.

**Usage:**
```bash
ruby download_ror_data.rb [options]
```

**Options:**
- `--data-dir DIR` - Directory to download files to (default: `data_files/`)
- `-h, --help` - Show help message

**Features:**
- Automatically fetches the latest ROR data from Zenodo using DOI [10.5281/zenodo.6347574](https://doi.org/10.5281/zenodo.6347574)
  - This DOI represents all versions and always resolves to the latest one
- Follows API redirects to get the current version
- Automatically detects the data format version (v2 or legacy v1) based on the zip filename
  - **v2 format**: Extracts files ending with `*schema.json` (when zip filename starts with "v2")
  - **Legacy v1 format**: Extracts files ending with `*schema_v2.json`
- Overwrites existing files if present
- Creates the data directory if it doesn't exist

**Output:** Downloads and extracts a file like:
- v2 format: `data_files/v2.XX-YYYY-MM-DD-ror-data_schema.json`
- Legacy v1 format: `data_files/v1.XX-YYYY-MM-DD-ror-data_schema_v2.json`

**Examples:**
```bash
# Use default data_files/ directory
ruby download_ror_data.rb

# Use custom directory
ruby download_ror_data.rb --data-dir custom_data/
```

### 2. `build_ror_data.rb`

Builds both funder-to-ROR mapping and organizational hierarchy from ROR data in a single pass.

**Usage:**
```bash
ruby build_ror_data.rb [options]
```

**Options:**
- `--data-dir DIR` - Directory containing ROR data files (default: `data_files/`)
- `--output-dir DIR` - Directory for output files (default: `output/`)
- `--input FILE` - Input ROR data file (overrides --data-dir search)
- `--funder-output FILE` - Output funder mapping file (default: `output/funder_to_ror.json`)
- `--hierarchy-output FILE` - Output hierarchy file (default: `output/ror_hierarchy.json`)
- `--gzip` - Require output files to end with `.gz` (validates file extensions)
- `--funder-only` - Build only the funder mapping (not hierarchy)
- `--hierarchy-only` - Build only the hierarchy (not funder mapping)
- `-h, --help` - Show help message

**Features:**
- Automatically finds the most recent ROR data file in the data directory (supports both v2 and legacy v1 formats)
- Uses streaming JSON parser (yajl-ruby) for better memory efficiency when available
- Creates funder ID to ROR ID mappings from Fundref external IDs
- Builds complete organizational hierarchies with ancestors and descendants
- Optimized storage: only includes organizations with actual hierarchical relationships
- Outputs JSON files (plain by default, or gzipped if file extension is `.gz`)
- Automatic format detection: files ending with `.json` are plain JSON, files ending with `.gz` are gzipped
- Provides statistics on mappings and hierarchies
- Build only what you need with `--funder-only` or `--hierarchy-only` flags
- Creates output directory if it doesn't exist

**Examples:**
```bash
# Build both funder mapping and hierarchy (default)
# Looks in data_files/ for input, writes to output/
ruby build_ror_data.rb

# Build only funder mapping
ruby build_ror_data.rb --funder-only

# Build only hierarchy
ruby build_ror_data.rb --hierarchy-only

# Use custom directories
ruby build_ror_data.rb --data-dir custom_data/ --output-dir custom_output/

# Specify custom input file (supports both v2 and legacy v1 formats)
ruby build_ror_data.rb --input data_files/v2.XX-YYYY-MM-DD-ror-data_schema.json
# or legacy v1 format:
ruby build_ror_data.rb --input data_files/v1.70-2025-08-26-ror-data_schema_v2.json
```

**Outputs:**
- `output/funder_to_ror.json` - Mapping of funder IDs to ROR IDs (plain JSON by default)
- `output/ror_hierarchy.json` - Organizational hierarchies with ancestors and descendants (only includes organizations with actual relationships, plain JSON by default)

**Output Format:**
- By default, files are written as plain JSON (`.json` extension)
- If you specify a file ending with `.gz`, it will be automatically gzipped
- Use the `--gzip` flag to require gzipped output (validates that output files end with `.gz`)

**Performance Notes:**
- Install `yajl-ruby` gem for streaming JSON parsing on large files: `bundle install`
- Hierarchy file only contains organizations with parent/child relationships, significantly reducing file size
- Use `--funder-only` or `--hierarchy-only` to process only what you need

### 3. `ror_hierarchy_lookup.rb`

Efficient lookup tool for querying organizational hierarchies and funder mappings.

**Command-Line Usage:**
```bash
ruby ror_hierarchy_lookup.rb <id> [options]
```

**Options:**
- `--data-dir DIR` - Directory containing generated files (default: `output/`)
- `--hierarchy-file FILE` - Path to hierarchy file (overrides --data-dir)
- `--funder-file FILE` - Path to funder mapping file (overrides --data-dir)
- `-h, --help` - Show help message

**Examples:**
```bash
# Look up by ROR ID (uses default output/ directory)
ruby ror_hierarchy_lookup.rb https://ror.org/02mhbdp94

# Look up by Funder ID
ruby ror_hierarchy_lookup.rb 100000001

# Use custom data directory
ruby ror_hierarchy_lookup.rb https://ror.org/02mhbdp94 --data-dir custom_output/

# Specify custom data files
ruby ror_hierarchy_lookup.rb https://ror.org/02mhbdp94 --hierarchy-file output/ror_hierarchy.json --funder-file output/funder_to_ror.json
```

**Programmatic Usage:**
```ruby
require_relative 'ror_hierarchy_lookup'

# Initialize the lookup (loads the gzipped data files from output/ by default)
lookup = RorHierarchyLookup.new

# Or specify custom file paths
lookup = RorHierarchyLookup.new('output/ror_hierarchy.json', 'output/funder_to_ror.json')

# Look up by ROR ID
result = lookup.lookup('https://ror.org/02mhbdp94')

# Look up by Funder ID
result = lookup.lookup('100000001')

# Result structure:
# {
#   org_id: "https://ror.org/02mhbdp94",
#   input_id: "100000001",
#   ancestors: ["https://ror.org/parent1", ...],
#   descendants: ["https://ror.org/child1", ...]
# }

# Get only ancestors
ancestors = lookup.ancestors('100000001')

# Get only descendants
descendants = lookup.descendants('https://ror.org/02mhbdp94')

# Check if organization has relationships
if lookup.has_ancestors?('100000001')
  puts "This organization has parent organizations"
end
```

**Features:**
- Command-line tool for quick lookups
- Ruby class for programmatic access
- Loads pre-built gzipped hierarchy and funder mapping files
- Supports lookup by both ROR IDs and Funder IDs
- Returns ancestors and descendants for any organization
- Returns `nil` for organizations not in the hierarchy (i.e., no relationships)
- Memory-efficient with compressed data

## Quick Start

1. **Download the latest ROR data:**
   ```bash
   ruby download_ror_data.rb
   ```

2. **Build the mappings and hierarchy:**
   ```bash
   ruby build_ror_data.rb
   ```

3. **Query the hierarchy:**
   ```bash
   # Command-line lookup
   ruby ror_hierarchy_lookup.rb 100000001
   ```
   
   Or use it in your code:
   ```ruby
   require_relative 'ror_hierarchy_lookup'
   
   lookup = RorHierarchyLookup.new
   result = lookup.lookup('100000001')  # Funder ID
   puts "Ancestors: #{result[:ancestors]}"
   puts "Descendants: #{result[:descendants]}"
   ```

## Data Files

After running the scripts, you'll have:

**In `data_files/` directory:**
- `v*.json` - Raw ROR data file (downloaded from Zenodo)
- `*.zip` - Downloaded zip files from Zenodo

**In `output/` directory:**
- `funder_to_ror.json` - Funder-to-ROR mapping (plain JSON by default)
- `ror_hierarchy.json` - Organizational hierarchy data (plain JSON by default)

## Workflow

```
┌─────────────────────────┐
│  download_ror_data.rb   │  Downloads latest ROR data
└───────────┬─────────────┘
            │
            ▼
    data_files/
    ├── v2.XX-YYYY-MM-DD-ror-data_schema.json
    └── (or legacy v1.XX-YYYY-MM-DD-ror-data_schema_v2.json)
            │
            ▼
┌─────────────────────────┐
│   build_ror_data.rb     │  Processes ROR data
└───────────┬─────────────┘
            │
            ▼
      output/
      ├── funder_to_ror.json
      └── ror_hierarchy.json
            │
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

**Note:** Only organizations with at least one ancestor or descendant are included in the hierarchy file. Organizations with no hierarchical relationships are omitted to reduce file size.

## About ROR

The Research Organization Registry (ROR) is a community-led registry of open, sustainable, usable, and unique identifiers for research organizations. Learn more at [ror.org](https://ror.org/).

## ROR Data
ROR data can always be found in Zenodo using the DOI [10.5281/zenodo.6347574](http://doi.org/10.5281/zenodo.6347574). This DOI represents all versions, and will always resolve to the latest one.

## License

This project is independent tooling for working with ROR data. ROR data is licensed under CC0 1.0 Universal.
