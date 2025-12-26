# Reader/Writer Callbacks Guide

## Обзор

EnvSettings поддерживает кастомные колбеки для чтения и записи переменных. Это позволяет использовать различные хранилища: базу данных, Redis, файлы, Vault и т.д.

## Основные принципы

### 1. По умолчанию все переменные read-only

```ruby

class Env < EnvSettings::Base
  var :database_url, type: :string
end

Env.database_url # ✅ Читает из ENV['DATABASE_URL']
Env.database_url = "new" # ❌ EnvSettings::ReadOnlyError
```

### 2. Reader определяет откуда читать

```ruby
var :api_key,
    reader: ->(key, setting) {
      # key = "API_KEY"
      # setting = { type: :string, default: nil, ... }
      Setting.find_by(key: key)&.value
    }
```

### 3. Writer определяет куда писать

```ruby
var :api_key,
    writer: ->(key, value, setting) {
      # key = "API_KEY"
      # value = то что присваивается
      # setting = { type: :string, default: nil, ... }
      Setting.find_or_create_by(key: key).update!(value: value)
    }
```

### 4. Глобальные колбеки для всех переменных

```ruby

class Env < EnvSettings::Base
  default_reader ->(key, setting) { Setting.get(key) || ENV[key] }
  default_writer ->(key, value, setting) { Setting.set(key, value) }

  # Все переменные используют эти колбеки
  var :api_key, type: :string
  var :timeout, type: :integer
end
```

## Практические сценарии

### Сценарий 1: Конфигурация в ENV (read-only)

**Задача:** Критичные настройки должны задаваться только через ENV.

```ruby

class Env < EnvSettings::Base
  # Читаем из ENV, запись запрещена
  var :database_url, type: :string, validates: { presence: true }
  var :secret_key, type: :string, validates: { presence: true }
  var :redis_url, type: :string, default: "redis://localhost:6379"
end

# Использование
Env.database_url # Читает из ENV
Env.database_url = "new" # ReadOnlyError
```

### Сценарий 2: Runtime настройки в базе данных

**Задача:** Настройки, которые можно менять через админку без перезапуска.

```ruby
# Модель ActiveRecord
class Setting < ApplicationRecord
  # Таблица: settings (key:string, value:text)

  def self.get(key)
    find_by(key: key)&.value
  end

  def self.set(key, value)
    find_or_create_by(key: key).update!(value: value.to_s)
  end
end

# EnvSettings
class Env < EnvSettings::Base
  # Глобальные колбеки для всех runtime-настроек
  default_reader ->(key, setting) {
    Setting.get(key) || ENV[key]
  }

  default_writer ->(key, value, setting) {
    Setting.set(key, value)
  }

  var :maintenance_mode, type: :boolean, default: false
  var :max_upload_size, type: :integer, default: 10_485_760
  var :feature_x_enabled, type: :boolean, default: false
end

# Использование
Env.maintenance_mode = true # Сохраняется в БД
Env.maintenance_mode # Читается из БД (или ENV если нет в БД)

# В админке
class AdminController < ApplicationController
  def toggle_maintenance
    Env.maintenance_mode = params[:enabled]
    redirect_to admin_path, notice: "Maintenance mode updated"
  end
end
```

### Сценарий 3: Feature flags в Redis

**Задача:** Быстрые feature flags с минимальной латентностью.

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

# Использование
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

### Сценарий 4: Секреты в Vault

**Задача:** Чтение секретов из HashiCorp Vault (только чтение).

```ruby
require 'vault'

Vault.address = ENV['VAULT_ADDR']
Vault.token = ENV['VAULT_TOKEN']

class Env < EnvSettings::Base
  # Обычные настройки из ENV
  var :database_url, type: :string

  # Секреты из Vault (read-only)
  var :stripe_secret_key,
      type: :string,
      reader: ->(key, setting) {
        secret = Vault.logical.read("secret/data/#{key}")
        secret&.data&.dig(:data, :value)
      }

  var :aws_secret_key,
      type: :string,
      reader: ->(key, setting) {
        secret = Vault.logical.read("secret/data/#{key}")
        secret&.data&.dig(:data, :value)
      }
end

# Использование
Stripe.api_key = Env.stripe_secret_key # Читается из Vault
Env.stripe_secret_key = "new" # ReadOnlyError (нет writer)
```

### Сценарий 5: Гибридная конфигурация

**Задача:** Разные переменные в разных хранилищах.

```ruby

class Env < EnvSettings::Base
  # 1. Критичные настройки: только ENV (read-only)
  var :database_url,
      type: :string,
      validates: { presence: true }

  # 2. Runtime настройки: база данных (read-write)
  var :maintenance_mode,
      type: :boolean,
      default: false,
      reader: ->(key, setting) { Setting.get(key) || ENV[key] },
      writer: ->(key, value, setting) { Setting.set(key, value) }

  # 3. Feature flags: Redis (read-write)
  var :features,
      type: :hash,
      default: {},
      reader: ->(key, setting) {
        JSON.parse(Redis.current.get("flags") || "{}")
      },
      writer: ->(key, value, setting) {
        Redis.current.set("flags", value.to_json)
      }

  # 4. Секреты: Vault (read-only)
  var :api_secret,
      type: :string,
      reader: ->(key, setting) {
        Vault.logical.read("secret/#{key}")&.data&.dig(:data, :value)
      }
end
```

### Сценарий 6: YAML файл для development

**Задача:** Локальные настройки в YAML файле для разработки.

```ruby

class Env < EnvSettings::Base
  SETTINGS_FILE = Rails.root.join("config/local_settings.yml")

  default_reader ->(key, setting) {
    if File.exist?(SETTINGS_FILE)
      YAML.load_file(SETTINGS_FILE)[key]
    else
      ENV[key]
    end
  }

  default_writer ->(key, value, setting) {
    data = File.exist?(SETTINGS_FILE) ? YAML.load_file(SETTINGS_FILE) : {}
    data[key] = value.to_s
    File.write(SETTINGS_FILE, data.to_yaml)
  }

  var :debug_mode, type: :boolean, default: false
  var :mock_external_api, type: :boolean, default: false
end

# config/local_settings.yml
# DEBUG_MODE: "true"
# MOCK_EXTERNAL_API: "true"

# В коде
Env.debug_mode = true # Записывается в YAML
```

## Приоритеты чтения

Порядок проверки при чтении:

1. **Индивидуальный reader** (если указан `reader:`)
2. **Глобальный default_reader** (если указан `default_reader`)
3. **ENV** (по умолчанию)
4. **Default** (если значение nil)

```ruby

class Env < EnvSettings::Base
  default_reader ->(key, setting) { Setting.get(key) }

  var :var1, default: "default1"
  var :var2, default: "default2", reader: ->(k, s) { "custom" }
end

# Var1: Setting.get("VAR1") → default1
# Var2: "custom" → default2
```

## Приоритеты записи

Порядок проверки при записи:

1. **Индивидуальный writer** (если указан `writer:`)
2. **Глобальный default_writer** (если указан `default_writer`)
3. **ReadOnlyError** (по умолчанию)

## Обработка ошибок

```ruby
# Перехват ошибки записи
begin
  Env.database_url = "new_value"
rescue EnvSettings::ReadOnlyError => e
  Rails.logger.warn "Попытка записи в read-only переменную: #{e.message}"
end

# Безопасная проверка перед записью
if Env.settings[:maintenance_mode][:writer]
  Env.maintenance_mode = true
else
  Rails.logger.info "maintenance_mode is read-only"
end
```

## Best Practices

### 1. Явно определяйте read-only переменные

```ruby
# ✅ Хорошо - понятно что это read-only
var :database_url, type: :string, validates: { presence: true }

# ❌ Плохо - неочевидно
var :database_url, type: :string, writer: nil
```

### 2. Используйте глобальные колбеки для однотипных переменных

```ruby
# ✅ Хорошо
class Env < EnvSettings::Base
  default_reader ->(key, s) { Setting.get(key) || ENV[key] }
  default_writer ->(key, value, s) { Setting.set(key, value) }

  var :var1, type: :string
  var :var2, type: :integer
end

# ❌ Плохо - дублирование
class Env < EnvSettings::Base
  var :var1,
      reader: ->(k, s) { Setting.get(k) || ENV[k] },
      writer: ->(k, v, s) { Setting.set(k, v) }

  var :var2,
      reader: ->(k, s) { Setting.get(k) || ENV[k] },
      writer: ->(k, v, s) { Setting.set(k, v) }
end
```

### 3. Кешируйте дорогие операции

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

### 4. Логируйте изменения

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

### 5. Валидация в колбеках

```ruby
var :max_connections,
    type: :integer,
    default: 10,
    writer: ->(key, value, setting) {
      if value.to_i > 100
        raise ArgumentError, "max_connections cannot exceed 100"
      end
      Setting.set(key, value)
    }
```
