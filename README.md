# EnvSettings

Type-safe environment variables management for Ruby applications with a clean DSL inspired by rails-settings-cached.

## Features

- Type-safe environment variable access
- Support for multiple types: string, integer, float, boolean, array, hash, symbol
- Built-in validations (presence, length, format, inclusion)
- Clean, Rails-like DSL
- Default values
- Boolean helper methods
- Custom reader/writer callbacks for flexible storage (database, Redis, files, etc.)
- Read-only by default for security
- ActiveModel validations support (optional)
- Fully tested

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'env_settings'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install env_settings
```

## Usage

### Basic Setup

Create a class that inherits from `EnvSettings::Base` and define your environment variables:

```ruby

class Env < EnvSettings::Base
  var :app_name, type: :string, default: "MyApp"
  var :port, type: :integer, default: 3000
  var :debug, type: :boolean, default: false
  var :database_url, type: :string, validates: { presence: true }
  var :allowed_hosts, type: :array, default: []
  var :redis_config, type: :hash, default: {}
end
```

By default, all variables are **read-only** and read from `ENV`. To enable writing or custom storage, see [Custom Reader/Writer Callbacks](#custom-readerwriter-callbacks).

### Reading Values

```ruby
# Simple access
Env.app_name          # => "MyApp"
Env.port              # => 3000

# Boolean helper
Env.debug?            # => false

# Presence check
Env.database_url_present?  # => true/false

# Get all settings as hash
Env.all               # => { app_name: "MyApp", port: 3000, ... }
Env.to_h              # Same as .all
```

### Setting Values

**Important:** By default, all variables are read-only. To enable writing, you must provide a `writer` callback.

```ruby
# This will raise ReadOnlyError
Env.app_name = "NewApp" # Raises EnvSettings::ReadOnlyError

# To make a variable writable, provide a writer callback
class Env < EnvSettings::Base
  var :app_name,
      type: :string,
      default: "MyApp",
      writer: ->(key, value, setting) { ENV[key] = value.to_s }
end

Env.app_name = "NewApp" # Works
```

### Supported Types

#### String (default)

```ruby
var :app_name, type: :string, default: "MyApp"
# ENV["APP_NAME"] = "MyApp" => "MyApp"
```

#### Integer

```ruby
var :port, type: :integer, default: 3000
# ENV["PORT"] = "5000" => 5000
```

#### Float

```ruby
var :price, type: :float, default: 9.99
# ENV["PRICE"] = "19.99" => 19.99
```

#### Boolean

```ruby
var :debug, type: :boolean, default: false
# ENV["DEBUG"] = "true"  => true
# ENV["DEBUG"] = "1"     => true
# ENV["DEBUG"] = "yes"   => true
# ENV["DEBUG"] = "on"    => true
# ENV["DEBUG"] = "false" => false
# ENV["DEBUG"] = "0"     => false

# Boolean helper method
Env.debug? # => true/false
```

#### Array

```ruby
var :allowed_hosts, type: :array, default: []

# JSON format
# ENV["ALLOWED_HOSTS"] = '["host1", "host2"]' => ["host1", "host2"]

# Comma-separated format
# ENV["ALLOWED_HOSTS"] = "host1, host2, host3" => ["host1", "host2", "host3"]
```

#### Hash

```ruby
var :redis_config, type: :hash, default: {}

# JSON format
# ENV["REDIS_CONFIG"] = '{"host": "localhost", "port": 6379}'
# => { "host" => "localhost", "port" => 6379 }
```

#### Symbol

```ruby
var :log_level, type: :symbol, default: :info
# ENV["LOG_LEVEL"] = "debug" => :debug
```

### Validations

#### Presence

```ruby
var :database_url, validates: { presence: true }
```

#### Length

```ruby
var :username, validates: {
  length: {
    minimum: 3,
    maximum: 20
  }
}

# Or with range
var :username, validates: {
  length: { in: 3..20 }
}
```

#### Format (Regex)

```ruby
var :email, validates: {
  format: { with: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i }
}

# With custom message
var :email, validates: {
  format: {
    with: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i,
    message: "must be a valid email address"
  }
}
```

#### Inclusion

```ruby
var :environment, validates: {
  inclusion: { in: %w[development test production] }
}
```

#### Multiple Validations

```ruby
var :api_key, validates: {
  presence: true,
  length: { minimum: 32 },
  format: { with: /\A[a-zA-Z0-9]+\z/ }
}
```

### Running Validations

```ruby
# Validate all settings at once
Env.validate!

# Will raise EnvSettings::ValidationError if any validation fails
```

It's recommended to run validations during application initialization:

```ruby
# config/initializers/env_settings.rb (Rails)
Env.validate!
```

### Automatic Validation on Write

When you assign a value to a variable with validations, it's automatically validated **before** writing to storage:

```ruby
class Env < EnvSettings::Base
  default_writer ->(key, value, setting) { Setting.find_or_create_by(key: key).update!(value: value) }

  var :username,
      type: :string,
      validates: { presence: true, length: { minimum: 3, maximum: 20 } }

  var :email,
      type: :string,
      validates: { format: { with: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i } }
end

# These will raise ValidationError BEFORE writing to database
Env.username = ""           # Raises: "Username can't be blank"
Env.username = "ab"         # Raises: "Username is too short (minimum is 3 characters)"
Env.email = "invalid"       # Raises: "Email is invalid"

# Only valid values are written to storage
Env.username = "john"       # Works - writes to database
Env.email = "j@example.com" # Works - writes to database
```

This prevents invalid data from being stored and ensures data integrity at the assignment level.

## ActiveModel Validations (Optional)

EnvSettings automatically uses ActiveModel validations if `activemodel` gem is available. This provides:

- More validation options (numericality, comparison, exclusion, etc.)
- Better error messages with I18n support
- Custom validators
- Full compatibility with Rails

### Installation with ActiveModel

```ruby
# Gemfile
gem 'env_settings'
gem 'activemodel'  # Optional, but recommended for Rails projects
```

### ActiveModel Validation Examples

```ruby
class Env < EnvSettings::Base
  # Numericality validation
  var :port,
      type: :integer,
      default: 3000,
      validates: {
        numericality: {
          only_integer: true,
          greater_than: 0,
          less_than: 65536
        }
      }

  var :timeout,
      type: :float,
      validates: {
        numericality: { greater_than_or_equal_to: 0 }
      }

  # Comparison validation
  var :min_value, type: :integer, default: 0
  var :max_value,
      type: :integer,
      default: 100,
      validates: {
        comparison: { greater_than: :min_value }
      }

  # Exclusion validation
  var :username,
      validates: {
        exclusion: { in: %w[admin root superuser] }
      }

  # Absence validation (for deprecated variables)
  var :legacy_option,
      validates: { absence: true }

  # Custom validators
  var :api_endpoint,
      validates: { url: true }  # Uses custom UrlValidator
end
```

### Validation Syntax

EnvSettings uses **ActiveModel-compatible validation syntax**. This means:

- **With ActiveModel** (`activemodel` gem installed): Full ActiveModel validations with rich features
- **Without ActiveModel**: Built-in simple validations with the same syntax but limited to: `presence`, `length`, `format`, `inclusion`

The syntax is identical in both cases, so your code works seamlessly:

```ruby
# This syntax works with AND without activemodel
var :email, validates: {
  presence: true,
  format: { with: /regex/, message: "is not valid" }
}

# ActiveModel-only validators (requires activemodel gem)
var :age, validates: {
  numericality: { greater_than: 0, less_than: 150 }  # Only with ActiveModel
}

var :password, validates: {
  confirmation: true  # Only with ActiveModel
}
```

**Recommendation**: Install `activemodel` gem for Rails projects to get full validation features.

### Rails Integration

Create an initializer:

```ruby
# config/initializers/var.rb
class Env < EnvSettings::Base
  var :app_name, type: :string, default: "MyRailsApp"
  var :port, type: :integer, default: 3000
  var :database_url, type: :string, validates: { presence: true }
  var :redis_url, type: :string, default: "redis://localhost:6379/0"
  var :smtp_host, type: :string
  var :smtp_port, type: :integer, default: 587
  var :enable_cache, type: :boolean, default: false
  var :allowed_hosts, type: :array, default: []
  var :environment, type: :string, validates: {
    inclusion: %w[development test staging production]
  }
end

# Validate on startup
Env.validate!
```

Then use throughout your application:

```ruby
# config/database.yml
default: &default
  url: <%= Env.database_url %>

# config/environments/production.rb
config.cache_store = :redis_cache_store, { url: Env.redis_url }

# Anywhere in your code
if Env.enable_cache?
  # Do something
end
```

## Custom Reader/Writer Callbacks

EnvSettings allows you to define custom callbacks for reading and writing variables, enabling flexible storage backends like databases, Redis, or files.

### Individual Variable Callbacks

```ruby

class Env < EnvSettings::Base
  # Read-only from ENV (default behavior)
  var :database_url, type: :string, validates: { presence: true }

  # Custom reader from database
  var :maintenance_mode,
      type: :boolean,
      default: false,
      reader: ->(key, setting) { Setting.find_by(key: key)&.value }

  # Custom reader and writer
  var :feature_flags,
      type: :hash,
      default: {},
      reader: ->(key, setting) {
        value = Redis.current.get("settings:#{key}")
        value ? JSON.parse(value) : nil
      },
      writer: ->(key, value, setting) {
        Redis.current.set("settings:#{key}", value.to_json)
      }
end

# Usage
Env.maintenance_mode # Reads from database
Env.feature_flags = { x: true } # Writes to Redis
Env.database_url = "new" # Raises ReadOnlyError (no writer)
```

### Global Default Callbacks

Set default reader/writer for all variables:

```ruby

class Env < EnvSettings::Base
  # All variables will use these callbacks by default
  default_reader ->(key, setting) {
    Setting.find_by(key: key)&.value || ENV[key]
  }

  default_writer ->(key, value, setting) {
    Setting.find_or_create_by(key: key).update!(value: value)
  }

  # Now all variables are readable/writable through database
  var :api_key, type: :string, default: "default_key"
  var :timeout, type: :integer, default: 30

  # Can override for specific variables
  var :secret_key,
      type: :string,
      reader: ->(key, setting) { ENV[key] }, # Only from ENV
      writer: nil # Explicitly read-only
end

# Block syntax is also supported
class Env < EnvSettings::Base
  default_reader do |key, setting|
    Setting.find_by(key: key)&.value || ENV[key]
  end

  default_writer do |key, value, setting|
    Setting.find_or_create_by(key: key).update!(value: value)
  end
end
```

### Callback Parameters

Callbacks receive the following parameters:

- `key` - The uppercase ENV key (e.g., "API_KEY")
- `setting` - Full configuration hash with: `:type`, `:default`, `:validates`, `:env_key`, etc.

**Reader callback:**
```ruby
reader: ->(key, setting) {
  # Must return raw value (string/nil)
  # Type coercion is applied automatically
}
```

**Writer callback:**
```ruby
writer: ->(key, value, setting) {
  # Receives the value to write
  # No return value expected
}
```

### Practical Examples

#### ActiveRecord Storage

```ruby

class Env < EnvSettings::Base
  default_reader ->(key, setting) {
    Setting.find_by(key: key)&.value || ENV[key]
  }

  default_writer ->(key, value, setting) {
    Setting.find_or_create_by(key: key).update!(value: value)
  }

  var :maintenance_mode, type: :boolean, default: false
  var :max_connections, type: :integer, default: 10
end
```

#### Redis Storage

```ruby

class Env < EnvSettings::Base
  default_reader ->(key, setting) {
    Redis.current.get("app:settings:#{key}")
  }

  default_writer ->(key, value, setting) {
    Redis.current.set("app:settings:#{key}", value.to_s)
  }

  var :rate_limit, type: :integer, default: 100
  var :feature_x_enabled, type: :boolean, default: false
end
```

#### YAML File Storage

```ruby

class Env < EnvSettings::Base
  SETTINGS_FILE = "config/runtime_settings.yml"

  default_reader ->(key, setting) {
    return ENV[key] unless File.exist?(SETTINGS_FILE)
    YAML.load_file(SETTINGS_FILE)[key]
  }

  default_writer ->(key, value, setting) {
    data = File.exist?(SETTINGS_FILE) ? YAML.load_file(SETTINGS_FILE) : {}
    data[key] = value.to_s
    File.write(SETTINGS_FILE, data.to_yaml)
  }

  var :log_level, type: :symbol, default: :info
end
```

#### Vault/Secrets Manager

```ruby

class Env < EnvSettings::Base
  var :api_key,
      type: :string,
      reader: ->(key, setting) {
        Vault.logical.read("secret/data/#{key}")&.data&.dig(:data, :value)
      },
      writer: ->(key, value, setting) {
        Vault.logical.write("secret/data/#{key}", data: { value: value })
      }
end
```

#### Mixed Strategy

```ruby

class Env < EnvSettings::Base
  # Default: read from ENV (no writer = read-only)
  var :database_url, type: :string, validates: { presence: true }

  # Runtime settings in database
  var :maintenance_mode,
      type: :boolean,
      default: false,
      reader: ->(key, setting) { Setting.get(key) },
      writer: ->(key, value, setting) { Setting.set(key, value) }

  # Feature flags in Redis
  var :feature_flags,
      type: :hash,
      default: {},
      reader: ->(key, setting) { JSON.parse(Redis.current.get(key) || "{}") },
      writer: ->(key, value, setting) { Redis.current.set(key, value.to_json) }

  # Secrets in Vault
  var :stripe_secret_key,
      type: :string,
      reader: ->(key, setting) { Vault.read("secret/#{key}") }
  # No writer = read-only
end
```

### Additional Use Cases

#### Runtime Configuration with Database

Settings that can be changed through admin panel without restart:

```ruby
# ActiveRecord model
class Setting < ApplicationRecord
  # Table: settings (key:string, value:text)

  def self.get(key)
    find_by(key: key)&.value
  end

  def self.set(key, value)
    find_or_create_by(key: key).update!(value: value.to_s)
  end
end

# EnvSettings configuration
class Env < EnvSettings::Base
  default_reader ->(key, setting) { Setting.get(key) || ENV[key] }
  default_writer ->(key, value, setting) { Setting.set(key, value) }

  var :maintenance_mode, type: :boolean, default: false
  var :max_upload_size, type: :integer, default: 10_485_760
  var :feature_x_enabled, type: :boolean, default: false
end

# Usage in admin controller
class AdminController < ApplicationController
  def toggle_maintenance
    Env.maintenance_mode = params[:enabled]
    redirect_to admin_path, notice: "Maintenance mode updated"
  end
end
```

#### Feature Flags with Redis

Fast feature flags with minimal latency:

```ruby
class Env < EnvSettings::Base
  var :feature_flags,
      type: :hash,
      default: {},
      reader: ->(key, setting) {
        value = Redis.current.get("flags:#{key}")
        value ? JSON.parse(value) : nil
      },
      writer: ->(key, value, setting) {
        Redis.current.set("flags:#{key}", value.to_json)
      }
end

# Usage
Env.feature_flags = {
  new_ui: true,
  beta_feature: false
}

if Env.feature_flags[:new_ui]
  render :new_design
else
  render :old_design
end
```

#### Caching Expensive Operations

```ruby
class Env < EnvSettings::Base
  @vault_cache = {}

  var :secret_key,
      reader: ->(key, setting) {
        @vault_cache[key] ||= begin
          secret = Vault.logical.read("secret/#{key}")
          secret&.data&.dig(:data, :value)
        end
      }
end
```

#### Logging Changes

```ruby
class Env < EnvSettings::Base
  default_writer ->(key, value, setting) {
    old_value = Setting.get(key)
    Setting.set(key, value)

    Rails.logger.info(
      "Setting changed: #{key} = #{value.inspect} (was: #{old_value.inspect})"
    )
  }
end
```

### Error Handling

```ruby
# ReadOnlyError is raised when trying to write without a writer
begin
  Env.database_url = "new_url"
rescue EnvSettings::ReadOnlyError => e
  puts e.message
  # => "Cannot write to 'database_url': variable is read-only. Provide a writer callback to enable writing."
end
```

## Example: Replacing ENV.fetch

**Before:**
```ruby
DATABASE_URL = ENV.fetch('DATABASE_URL')
PORT = ENV.fetch('PORT', 3000).to_i
DEBUG = ENV.fetch('DEBUG', 'false') == 'true'
ALLOWED_HOSTS = ENV.fetch('ALLOWED_HOSTS', '').split(',').map(&:strip)
```

**After:**

```ruby

class Env < EnvSettings::Base
  var :database_url, validates: { presence: true }
  var :port, type: :integer, default: 3000
  var :debug, type: :boolean, default: false
  var :allowed_hosts, type: :array, default: []
end

Env.database_url
Env.port
Env.debug?
Env.allowed_hosts
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.

## Testing

```bash
bundle exec rspec
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ekzo-dev/env_settings.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
