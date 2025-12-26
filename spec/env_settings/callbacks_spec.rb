# frozen_string_literal: true

require "spec_helper"

RSpec.describe EnvSettings::Base, "callbacks" do
  before do
    ENV.clear
  end

  describe "custom reader callback" do
    let(:storage) { {} }

    let(:test_class) do
      test_storage = storage
      Class.new(EnvSettings::Base) do
        env :api_key,
            type: :string,
            default: "default_key",
            reader: ->(key, setting) { test_storage[key] }

        env :timeout,
            type: :integer,
            default: 30,
            reader: ->(key, setting) { test_storage[key] }
      end
    end

    it "uses custom reader when provided" do
      storage["API_KEY"] = "custom_value"
      expect(test_class.api_key).to eq("custom_value")
    end

    it "returns default when custom reader returns nil" do
      expect(test_class.api_key).to eq("default_key")
    end

    it "applies type coercion to custom reader result" do
      storage["TIMEOUT"] = "60"
      expect(test_class.timeout).to eq(60)
      expect(test_class.timeout).to be_a(Integer)
    end

    it "ignores ENV when custom reader is provided" do
      ENV["API_KEY"] = "from_env"
      storage["API_KEY"] = "from_custom"
      expect(test_class.api_key).to eq("from_custom")
    end
  end

  describe "custom writer callback" do
    let(:storage) { {} }

    let(:test_class) do
      test_storage = storage
      Class.new(EnvSettings::Base) do
        env :api_key,
            type: :string,
            default: "default_key",
            reader: ->(key, setting) { test_storage[key] },
            writer: ->(key, value, setting) { test_storage[key] = value }

        env :feature_flag,
            type: :boolean,
            default: false,
            reader: ->(key, setting) { test_storage[key] },
            writer: ->(key, value, setting) { test_storage[key] = value }
      end
    end

    it "uses custom writer when provided" do
      test_class.api_key = "new_value"
      expect(storage["API_KEY"]).to eq("new_value")
    end

    it "allows reading written value through custom reader" do
      test_class.api_key = "new_value"
      expect(test_class.api_key).to eq("new_value")
    end

    it "passes raw value to writer (before type coercion)" do
      test_class.feature_flag = true
      expect(storage["FEATURE_FLAG"]).to eq(true)
    end

    it "does not write to ENV when custom writer is provided" do
      test_class.api_key = "new_value"
      expect(ENV["API_KEY"]).to be_nil
    end
  end

  describe "read-only variables (no writer)" do
    let(:test_class) do
      Class.new(EnvSettings::Base) do
        env :database_url, type: :string, default: "default_db"

        env :api_endpoint,
            type: :string,
            reader: ->(key, setting) { "https://api.example.com" }
      end
    end

    it "raises ReadOnlyError when trying to write to variable without writer" do
      expect { test_class.database_url = "new_url" }.to raise_error(
        EnvSettings::ReadOnlyError,
        /Cannot write to 'database_url': variable is read-only/
      )
    end

    it "raises ReadOnlyError for custom reader without writer" do
      expect { test_class.api_endpoint = "new_url" }.to raise_error(
        EnvSettings::ReadOnlyError,
        /Cannot write to 'api_endpoint': variable is read-only/
      )
    end
  end

  describe "default_reader class method" do
    let(:storage) { {} }

    let(:test_class) do
      test_storage = storage
      Class.new(EnvSettings::Base) do
        # Set default reader for all variables
        default_reader ->(key, setting) { test_storage[key] || ENV[key] }

        env :api_key, type: :string, default: "default_key"
        env :timeout, type: :integer, default: 30

        # This one overrides the default reader
        env :special_key,
            type: :string,
            reader: ->(key, setting) { "always_special" }
      end
    end

    it "uses default_reader for all variables" do
      storage["API_KEY"] = "from_storage"
      expect(test_class.api_key).to eq("from_storage")
    end

    it "falls back to ENV when storage returns nil" do
      ENV["API_KEY"] = "from_env"
      expect(test_class.api_key).to eq("from_env")
    end

    it "applies type coercion to default_reader result" do
      storage["TIMEOUT"] = "60"
      expect(test_class.timeout).to eq(60)
    end

    it "allows individual env to override default_reader" do
      storage["SPECIAL_KEY"] = "from_storage"
      expect(test_class.special_key).to eq("always_special")
    end
  end

  describe "default_writer class method" do
    let(:storage) { {} }

    let(:test_class) do
      test_storage = storage
      Class.new(EnvSettings::Base) do
        # Set default writer for all variables
        default_reader ->(key, setting) { test_storage[key] }
        default_writer ->(key, value, setting) { test_storage[key] = value }

        env :api_key, type: :string, default: "default_key"
        env :timeout, type: :integer, default: 30

        # This one overrides the default writer
        env :special_key,
            type: :string,
            writer: ->(key, value, setting) { test_storage["CUSTOM_#{key}"] = value }
      end
    end

    it "uses default_writer for all variables" do
      test_class.api_key = "new_value"
      expect(storage["API_KEY"]).to eq("new_value")
    end

    it "allows individual env to override default_writer" do
      test_class.special_key = "special_value"
      expect(storage["CUSTOM_SPECIAL_KEY"]).to eq("special_value")
      expect(storage["SPECIAL_KEY"]).to be_nil
    end

    it "allows reading written value" do
      test_class.api_key = "new_value"
      expect(test_class.api_key).to eq("new_value")
    end
  end

  describe "default_reader with block syntax" do
    let(:storage) { {} }

    let(:test_class) do
      test_storage = storage
      Class.new(EnvSettings::Base) do
        default_reader do |key, setting|
          test_storage[key]
        end

        env :api_key, type: :string, default: "default_key"
      end
    end

    it "accepts block syntax for default_reader" do
      storage["API_KEY"] = "from_block"
      expect(test_class.api_key).to eq("from_block")
    end
  end

  describe "default_writer with block syntax" do
    let(:storage) { {} }

    let(:test_class) do
      test_storage = storage
      Class.new(EnvSettings::Base) do
        default_reader { |key, setting| test_storage[key] }
        default_writer { |key, value, setting| test_storage[key] = value }

        env :api_key, type: :string, default: "default_key"
      end
    end

    it "accepts block syntax for default_writer" do
      test_class.api_key = "from_block"
      expect(storage["API_KEY"]).to eq("from_block")
    end
  end

  describe "callback receives setting context" do
    let(:captured_settings) { [] }

    let(:test_class) do
      captured = captured_settings
      Class.new(EnvSettings::Base) do
        env :api_key,
            type: :string,
            default: "default_key",
            validates: { presence: true },
            reader: ->(key, setting) {
              captured << setting
              "test_value"
            }
      end
    end

    it "passes full setting configuration to reader" do
      test_class.api_key
      setting = captured_settings.first

      expect(setting[:type]).to eq(:string)
      expect(setting[:default]).to eq("default_key")
      expect(setting[:env_key]).to eq("API_KEY")
      expect(setting[:validates]).to eq({ presence: true })
    end
  end

  describe "mixed configuration scenarios" do
    let(:storage) { {} }

    let(:test_class) do
      test_storage = storage
      Class.new(EnvSettings::Base) do
        # Default reader but no default writer
        default_reader ->(key, setting) { test_storage[key] || ENV[key] }

        # Read-only from storage
        env :database_url, type: :string, default: "default_db"

        # Writable to storage
        env :api_key,
            type: :string,
            writer: ->(key, value, setting) { test_storage[key] = value }

        # Completely custom
        env :feature_flag,
            type: :boolean,
            reader: ->(key, setting) { test_storage["custom_#{key}"] },
            writer: ->(key, value, setting) { test_storage["custom_#{key}"] = value }
      end
    end

    it "allows read-only variables with default_reader" do
      storage["DATABASE_URL"] = "from_storage"
      expect(test_class.database_url).to eq("from_storage")

      expect { test_class.database_url = "new_url" }.to raise_error(
        EnvSettings::ReadOnlyError
      )
    end

    it "allows writable variables without custom reader" do
      ENV["API_KEY"] = "from_env"
      expect(test_class.api_key).to eq("from_env")

      test_class.api_key = "new_key"
      expect(storage["API_KEY"]).to eq("new_key")
    end

    it "allows fully custom read/write" do
      test_class.feature_flag = true
      expect(storage["custom_FEATURE_FLAG"]).to eq(true)
      expect(test_class.feature_flag).to eq(true)
    end
  end

  describe "backward compatibility" do
    let(:test_class) do
      Class.new(EnvSettings::Base) do
        env :app_name, type: :string, default: "TestApp"
        env :port, type: :integer, default: 3000
      end
    end

    it "still reads from ENV by default" do
      ENV["APP_NAME"] = "MyApp"
      expect(test_class.app_name).to eq("MyApp")
    end

    it "raises ReadOnlyError when trying to write without callbacks" do
      expect { test_class.app_name = "NewApp" }.to raise_error(
        EnvSettings::ReadOnlyError
      )
    end

    it "returns default when ENV not set" do
      expect(test_class.app_name).to eq("TestApp")
    end
  end
end
