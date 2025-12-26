# EnvSettings

Type-safe environment variables management for Ruby applications with a clean DSL inspired by rails-settings-cached.

## Features

- 🔒 Type-safe environment variable access
- 🎯 Support for multiple types: string, integer, float, boolean, array, hash, symbol
- ✅ Built-in validations (presence, length, format, inclusion)
- 🎨 Clean, Rails-like DSL
- 📝 Default values
- 🔍 Boolean helper methods
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

```ruby
Env.app_name = "NewApp"
Env.port = 8080
```

Note: Setting values updates the actual `ENV` hash.

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
