# frozen_string_literal: true

require "spec_helper"

RSpec.describe EnvSettings::Base do
  let(:test_class) do
    Class.new(EnvSettings::Base) do
      var :app_name, type: :string, default: "TestApp"
      var :port, type: :integer, default: 3000
      var :debug, type: :boolean, default: false
      var :database_url, validates: { presence: true }
      var :api_keys, type: :array, default: []
      var :config, type: :hash, default: {}
    end
  end

  before do
    ENV.clear
  end

  describe ".var" do
    it "defines getter method" do
      expect(test_class).to respond_to(:app_name)
    end

    it "defines setter method" do
      expect(test_class).to respond_to(:app_name=)
    end

    it "defines boolean helper for boolean type" do
      expect(test_class).to respond_to(:debug?)
    end

    it "defines presence check method" do
      expect(test_class).to respond_to(:app_name_present?)
    end
  end

  describe "type coercion" do
    context "string type" do
      it "returns string value from ENV" do
        ENV["APP_NAME"] = "MyApp"
        expect(test_class.app_name).to eq("MyApp")
      end

      it "returns default when ENV not set" do
        expect(test_class.app_name).to eq("TestApp")
      end
    end

    context "integer type" do
      it "converts ENV value to integer" do
        ENV["PORT"] = "5000"
        expect(test_class.port).to eq(5000)
      end

      it "returns default integer when ENV not set" do
        expect(test_class.port).to eq(3000)
      end
    end

    context "boolean type" do
      it "returns true for 'true'" do
        ENV["DEBUG"] = "true"
        expect(test_class.debug).to be true
      end

      it "returns true for '1'" do
        ENV["DEBUG"] = "1"
        expect(test_class.debug).to be true
      end

      it "returns true for 'yes'" do
        ENV["DEBUG"] = "yes"
        expect(test_class.debug).to be true
      end

      it "returns false for 'false'" do
        ENV["DEBUG"] = "false"
        expect(test_class.debug).to be false
      end

      it "returns false for any other value" do
        ENV["DEBUG"] = "no"
        expect(test_class.debug).to be false
      end

      it "works with boolean helper method" do
        ENV["DEBUG"] = "true"
        expect(test_class.debug?).to be true
      end
    end

    context "array type" do
      it "parses JSON array" do
        ENV["API_KEYS"] = '["key1", "key2", "key3"]'
        expect(test_class.api_keys).to eq(["key1", "key2", "key3"])
      end

      it "parses comma-separated values" do
        ENV["API_KEYS"] = "key1, key2, key3"
        expect(test_class.api_keys).to eq(["key1", "key2", "key3"])
      end

      it "returns default empty array" do
        expect(test_class.api_keys).to eq([])
      end
    end

    context "hash type" do
      it "parses JSON object" do
        ENV["CONFIG"] = '{"timeout": 30, "retries": 3}'
        expect(test_class.config).to eq({ "timeout" => 30, "retries" => 3 })
      end

      it "returns default empty hash" do
        expect(test_class.config).to eq({})
      end
    end
  end

  describe "setter methods" do
    it "raises ReadOnlyError when no writer is defined" do
      expect { test_class.app_name = "NewApp" }.to raise_error(
        EnvSettings::ReadOnlyError,
        /Cannot write to 'app_name': variable is read-only/
      )
    end

    it "raises ReadOnlyError for integer type without writer" do
      expect { test_class.port = 8080 }.to raise_error(
        EnvSettings::ReadOnlyError,
        /Cannot write to 'port': variable is read-only/
      )
    end

    context "with custom writer" do
      let(:writable_class) do
        Class.new(EnvSettings::Base) do
          var :app_name,
              type: :string,
              default: "TestApp",
              writer: ->(key, value, setting) { ENV[key] = value.to_s }

          var :port,
              type: :integer,
              default: 3000,
              writer: ->(key, value, setting) { ENV[key] = value.to_s }
        end
      end

      it "sets ENV variable when writer is defined" do
        writable_class.app_name = "NewApp"
        expect(ENV["APP_NAME"]).to eq("NewApp")
      end

      it "converts value to string when writer is defined" do
        writable_class.port = 8080
        expect(ENV["PORT"]).to eq("8080")
      end
    end
  end

  describe ".validate!" do
    context "presence validation" do
      it "raises error when required field is missing" do
        expect { test_class.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /Database url can't be blank/
        )
      end

      it "passes when required field is set" do
        ENV["DATABASE_URL"] = "postgresql://localhost/db"
        expect { test_class.validate! }.not_to raise_error
      end
    end

    context "length validation" do
      let(:test_class_with_length) do
        Class.new(EnvSettings::Base) do
          var :username, validates: { length: { minimum: 3, maximum: 20 } }
        end
      end

      it "raises error when value is too short" do
        ENV["USERNAME"] = "ab"
        expect { test_class_with_length.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /too short/
        )
      end

      it "raises error when value is too long" do
        ENV["USERNAME"] = "a" * 25
        expect { test_class_with_length.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /too long/
        )
      end

      it "passes when value length is valid" do
        ENV["USERNAME"] = "john"
        expect { test_class_with_length.validate! }.not_to raise_error
      end
    end

    context "format validation" do
      let(:test_class_with_format) do
        Class.new(EnvSettings::Base) do
          var :email, validates: { format: { with: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i } }
        end
      end

      it "raises error when format is invalid" do
        ENV["EMAIL"] = "invalid-email"
        expect { test_class_with_format.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /Email is invalid/
        )
      end

      it "passes when format is valid" do
        ENV["EMAIL"] = "user@example.com"
        expect { test_class_with_format.validate! }.not_to raise_error
      end
    end

    context "inclusion validation" do
      let(:test_class_with_inclusion) do
        Class.new(EnvSettings::Base) do
          var :environment, validates: { inclusion: { in: %w[development test production] } }
        end
      end

      it "raises error when value is not in list" do
        ENV["ENVIRONMENT"] = "staging"
        expect { test_class_with_inclusion.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /is not included in the list/
        )
      end

      it "passes when value is in list" do
        ENV["ENVIRONMENT"] = "production"
        expect { test_class_with_inclusion.validate! }.not_to raise_error
      end
    end
  end

  describe ".all" do
    it "returns hash of all settings with their values" do
      ENV["APP_NAME"] = "MyApp"
      ENV["PORT"] = "5000"

      result = test_class.all

      expect(result).to include(
        app_name: "MyApp",
        port: 5000
      )
    end
  end

  describe ".to_h" do
    it "returns hash representation" do
      expect(test_class.to_h).to be_a(Hash)
    end
  end

  describe "presence check" do
    it "returns false when value is nil" do
      expect(test_class.database_url_present?).to be false
    end

    it "returns false when value is empty string" do
      ENV["DATABASE_URL"] = ""
      expect(test_class.database_url_present?).to be false
    end

    it "returns true when value is present" do
      ENV["DATABASE_URL"] = "postgresql://localhost/db"
      expect(test_class.database_url_present?).to be true
    end
  end
end
