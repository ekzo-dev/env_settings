# EnvSettings - Development Context

## Project Overview

EnvSettings is a Ruby gem for type-safe environment variables management with a clean DSL inspired by rails-settings-cached.

## Created On
November 17, 2025

## Project Structure

```
env_settings/
├── lib/
│   ├── env_settings.rb           # Main entry point
│   ├── env_settings/
│   │   ├── version.rb            # Version definition
│   │   └── base.rb               # Core DSL and functionality
├── spec/
│   ├── spec_helper.rb
│   ├── env_settings_spec.rb      # Basic gem specs
│   └── env_settings/
│       └── base_spec.rb          # Comprehensive Base class specs
├── env_settings.gemspec          # Gem specification
├── README.md                     # User documentation
├── Gemfile
└── Rakefile
```

## Key Features Implemented

### 1. DSL for Defining Environment Variables

```ruby

class Env < EnvSettings::Base
   var :app_name, type: :string, default: "MyApp"
   var :port, type: :integer, default: 3000
   var :debug, type: :boolean, default: false
end
```

### 2. Type Coercion
Supported types:
- `:string` (default)
- `:integer`
- `:float`
- `:boolean` (accepts: "true", "1", "yes", "on")
- `:array` (parses JSON or comma-separated values)
- `:hash` (parses JSON objects)
- `:symbol`

### 3. Validations
- `presence: true` - ensures value is not nil or empty
- `length: { minimum: X, maximum: Y, in: Range }` - validates string length
- `format: /regex/` - validates against regex pattern
- `inclusion: [values]` - validates value is in allowed list

### 4. Helper Methods
Each defined var variable gets:
- Getter: `Env.app_name`
- Setter: `Env.app_name = "value"`
- Boolean helper (for boolean types): `Env.debug?`
- Presence check: `Env.app_name_present?`

### 5. Utility Methods
- `Env.all` / `Env.to_h` - returns hash of all settings
- `Env.validate!` - validates all settings at once

## Implementation Details

### Base Class (`lib/env_settings/base.rb`)

The Base class uses Ruby's metaprogramming to dynamically create methods:

1. **`var` method**: Main DSL method that:
   - Stores setting configuration in `@settings` hash
   - Defines getter/setter methods dynamically
   - Creates boolean helper methods for boolean types
   - Creates presence check methods

2. **Type Coercion**: `coerce_value` method handles conversion from string ENV values to proper types

3. **Validation**: `validate!` method iterates through all settings and applies configured validations

4. **Value Storage**: Values are read from `ENV` hash using uppercase variable names
   - `var :app_name` maps to `ENV['APP_NAME']`

## Testing

Full test coverage with RSpec:
- 37 examples, 0 failures
- Tests cover all types, validations, and helper methods
- Location: `spec/env_settings/base_spec.rb`

Run tests:
```bash
bundle exec rspec
```

## Usage Example

```ruby
# Define settings
class Env < EnvSettings::Base
  var :database_url, validates: { presence: true }
  var :port, type: :integer, default: 3000
  var :debug, type: :boolean, default: false
  var :allowed_hosts, type: :array, default: []
end

# Use in application
Env.database_url      # => "postgresql://localhost/mydb"
Env.port              # => 3000
Env.debug?            # => false
Env.allowed_hosts     # => ["localhost", "127.0.0.1"]

# Validate on startup
Env.validate!         # Raises ValidationError if required fields missing
```

## Recent Updates

### Custom Reader/Writer Callbacks (Added December 2025)

The library now supports custom reader/writer callbacks, enabling flexible storage backends:

**Key features:**
- Individual variable callbacks via `reader:` and `writer:` options
- Global callbacks via `default_reader` and `default_writer` class methods
- Read-only by default (raises `ReadOnlyError` without writer)
- Callbacks receive `key` and `setting` parameters for context
- Type coercion still applied to reader results
- Full backward compatibility

**Usage:**

```ruby

class Env < EnvSettings::Base
   # Custom callbacks per variable
   var :api_key,
       reader: ->(key, setting) { Setting.get(key) },
       writer: ->(key, value, setting) { Setting.set(key, value) }

   # Global defaults for all variables
   default_reader ->(key, setting) { Setting.get(key) || ENV[key] }
   default_writer ->(key, value, setting) { Setting.set(key, value) }
end
```

**Implementation details:**
- `ReadOnlyError` exception for write attempts without writer
- `get_value` checks: custom reader → default_reader → ENV
- `set_value` checks: custom writer → default_writer → raise ReadOnlyError
- 28 new tests added in `spec/env_settings/callbacks_spec.rb`

### ActiveModel Integration & Unified Syntax (December 2025)

**Unified validation syntax:**
- All validations now use ActiveModel-compatible syntax
- `format: { with: /regex/ }` instead of `format: /regex/`
- `inclusion: { in: array }` instead of `inclusion: array`
- Works with and without ActiveModel gem

**ActiveModel integration:**
- Optional dependency on `activemodel` gem
- Automatic detection and usage when available
- Validator class pattern for compatibility
- Full test coverage: 87 tests passing

**Method renamed:**
- `env` → `var` to avoid redundancy
- Cleaner API: `var :name` instead of `env :name`

## Next Steps / TODO

Potential enhancements:
- [ ] Add support for nested environment variables
- [ ] Add caching mechanism for parsed values
- [ ] Add support for .env file loading
- [ ] Add Rails generator for creating Env class
- [ ] Add support for environment-specific defaults
- [ ] Add documentation generation from definitions
- [x] ~~Add support for encrypted environment variables~~ (achieved via reader callbacks)
- [x] ~~Integration with popular secret management tools~~ (achieved via reader callbacks)
- [x] ~~ActiveModel validations support~~ (completed December 2025)
- [x] ~~Unified validation syntax~~ (completed December 2025)

## Development Notes

### Environment Variable Naming
The gem automatically converts Ruby method names to uppercase ENV variable names:
- `var :app_name` → `ENV['APP_NAME']`
- `var :database_url` → `ENV['DATABASE_URL']`

### Type Safety
The gem ensures type safety by:
1. Coercing string ENV values to specified types
2. Validating values before use (when validate! is called)
3. Providing type-specific helper methods

### Metaprogramming
The gem uses Ruby's metaprogramming capabilities:
- `define_singleton_method` for creating class methods
- `class << self` for class-level method definitions
- Dynamic method creation based on configuration

## Comparison with Similar Gems

### vs rails-settings-cached
- **rails-settings-cached**: Database-backed settings with caching
- **env_settings**: Environment variable-backed, no database required
- Both use similar DSL syntax
- env_settings is lighter weight and cloud-native friendly

### vs dotenv
- **dotenv**: Loads .var files into ENV
- **env_settings**: Provides type-safe access layer on top of ENV
- Can be used together: dotenv loads, env_settings provides typed access

### vs figaro
- **figaro**: YAML-based configuration loaded into ENV
- **env_settings**: Type-safe access layer with validations
- Similar use case, but env_settings adds type safety and validations

## Author
Created for Ekzo Platform
