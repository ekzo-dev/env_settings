# EnvSettings

Type-safe environment variables management for Ruby applications with a clean DSL inspired by rails-settings-cached.

## Features

- 🔒 Type-safe environment variable access
- 🎯 Support for multiple types: string, integer, float, boolean, array, hash, symbol
- ✅ Built-in validations (presence, length, format, inclusion)
- 🎨 Clean, Rails-like DSL
- 📝 Default values
- 🔍 Boolean helper methods
- 🔄 Custom reader/writer callbacks for flexible storage (database, Redis, files, etc.)
- 🛡️ Read-only by default for security
- 🧪 Fully tested

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
  env :app_name, type: :string, default: "MyApp"
  env :port, type: :integer, default: 3000
  env :debug, type: :boolean, default: false
  env :database_url, type: :string, validates: { presence: true }
  env :allowed_hosts, type: :array, default: []
  env :redis_config, type: :hash, default: {}
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
Env.app_name = "NewApp"  # ❌ EnvSettings::ReadOnlyError

# To make a variable writable, provide a writer callback
class Env < EnvSettings::Base
  env :app_name,
      type: :string,
      default: "MyApp",
      writer: ->(key, value, setting) { ENV[key] = value.to_s }
end

Env.app_name = "NewApp"  # ✅ Works
```

### Supported Types

#### String (default)
```ruby
env :app_name, type: :string, default: "MyApp"
# ENV["APP_NAME"] = "MyApp" => "MyApp"
```

#### Integer
```ruby
env :port, type: :integer, default: 3000
# ENV["PORT"] = "5000" => 5000
```

#### Float
```ruby
env :price, type: :float, default: 9.99
# ENV["PRICE"] = "19.99" => 19.99
```

#### Boolean
```ruby
env :debug, type: :boolean, default: false
# ENV["DEBUG"] = "true"  => true
# ENV["DEBUG"] = "1"     => true
# ENV["DEBUG"] = "yes"   => true
# ENV["DEBUG"] = "on"    => true
# ENV["DEBUG"] = "false" => false
# ENV["DEBUG"] = "0"     => false

# Boolean helper method
Env.debug?  # => true/false
```

#### Array
```ruby
env :allowed_hosts, type: :array, default: []

# JSON format
# ENV["ALLOWED_HOSTS"] = '["host1", "host2"]' => ["host1", "host2"]

# Comma-separated format
# ENV["ALLOWED_HOSTS"] = "host1, host2, host3" => ["host1", "host2", "host3"]
```

#### Hash
```ruby
env :redis_config, type: :hash, default: {}

# JSON format
# ENV["REDIS_CONFIG"] = '{"host": "localhost", "port": 6379}'
# => { "host" => "localhost", "port" => 6379 }
```

#### Symbol
```ruby
env :log_level, type: :symbol, default: :info
# ENV["LOG_LEVEL"] = "debug" => :debug
```

### Validations

#### Presence
```ruby
env :database_url, validates: { presence: true }
```

#### Length
```ruby
env :username, validates: {
  length: {
    minimum: 3,
    maximum: 20
  }
}

# Or with range
env :username, validates: {
  length: { in: 3..20 }
}
```

#### Format (Regex)
```ruby
env :email, validates: {
  format: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
}
```

#### Inclusion
```ruby
env :environment, validates: {
  inclusion: %w[development test production]
}
```

#### Multiple Validations
```ruby
env :api_key, validates: {
  presence: true,
  length: { minimum: 32 },
  format: /\A[a-zA-Z0-9]+\z/
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

### Rails Integration

Create an initializer:

```ruby
# config/initializers/env.rb
class Env < EnvSettings::Base
  env :app_name, type: :string, default: "MyRailsApp"
  env :port, type: :integer, default: 3000
  env :database_url, type: :string, validates: { presence: true }
  env :redis_url, type: :string, default: "redis://localhost:6379/0"
  env :smtp_host, type: :string
  env :smtp_port, type: :integer, default: 587
  env :enable_cache, type: :boolean, default: false
  env :allowed_hosts, type: :array, default: []
  env :environment, type: :string, validates: {
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
  env :database_url, type: :string, validates: { presence: true }

  # Custom reader from database
  env :maintenance_mode,
      type: :boolean,
      default: false,
      reader: ->(key, setting) { Setting.find_by(key: key)&.value }

  # Custom reader and writer
  env :feature_flags,
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
Env.maintenance_mode           # Reads from database
Env.feature_flags = { x: true } # Writes to Redis
Env.database_url = "new"       # ❌ ReadOnlyError (no writer)
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
  env :api_key, type: :string, default: "default_key"
  env :timeout, type: :integer, default: 30

  # Can override for specific variables
  env :secret_key,
      type: :string,
      reader: ->(key, setting) { ENV[key] },  # Only from ENV
      writer: nil                              # Explicitly read-only
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

  env :maintenance_mode, type: :boolean, default: false
  env :max_connections, type: :integer, default: 10
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

  env :rate_limit, type: :integer, default: 100
  env :feature_x_enabled, type: :boolean, default: false
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

  env :log_level, type: :symbol, default: :info
end
```

#### Vault/Secrets Manager

```ruby
class Env < EnvSettings::Base
  env :api_key,
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
  env :database_url, type: :string, validates: { presence: true }

  # Runtime settings in database
  env :maintenance_mode,
      type: :boolean,
      default: false,
      reader: ->(key, setting) { Setting.get(key) },
      writer: ->(key, value, setting) { Setting.set(key, value) }

  # Feature flags in Redis
  env :feature_flags,
      type: :hash,
      default: {},
      reader: ->(key, setting) { JSON.parse(Redis.current.get(key) || "{}") },
      writer: ->(key, value, setting) { Redis.current.set(key, value.to_json) }

  # Secrets in Vault
  env :stripe_secret_key,
      type: :string,
      reader: ->(key, setting) { Vault.read("secret/#{key}") }
      # No writer = read-only
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
  env :database_url, validates: { presence: true }
  env :port, type: :integer, default: 3000
  env :debug, type: :boolean, default: false
  env :allowed_hosts, type: :array, default: []
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
