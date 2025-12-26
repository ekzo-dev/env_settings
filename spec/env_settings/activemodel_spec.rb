# frozen_string_literal: true

require "spec_helper"

RSpec.describe EnvSettings::Base, "ActiveModel integration" do
  before do
    ENV.clear
  end

  context "when ActiveModel is available" do
    it "uses ActiveModel::Validations through validator_class" do
      test_class = Class.new(EnvSettings::Base) do
        var :test, validates: { presence: true }
      end

      expect(test_class.validator_class.ancestors).to include(ActiveModel::Validations)
    end

    describe "numericality validation" do
      let(:test_class) do
        Class.new(EnvSettings::Base) do
          var :age,
              type: :integer,
              default: 0,
              validates: {
                numericality: {
                  only_integer: true,
                  greater_than: 0,
                  less_than: 150
                }
              }

          var :price,
              type: :float,
              default: 0.0,
              validates: {
                numericality: {
                  greater_than_or_equal_to: 0
                }
              }
        end
      end

      it "validates numericality with greater_than" do
        ENV["AGE"] = "0"
        expect { test_class.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /Age must be greater than 0/
        )
      end

      it "validates numericality with less_than" do
        ENV["AGE"] = "150"
        expect { test_class.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /Age must be less than 150/
        )
      end

      it "passes when numericality is valid" do
        ENV["AGE"] = "25"
        ENV["PRICE"] = "19.99"
        expect { test_class.validate! }.not_to raise_error
      end

      it "validates float numericality" do
        ENV["PRICE"] = "-10.5"
        expect { test_class.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /Price must be greater than or equal to 0/
        )
      end
    end

    describe "comparison validation" do
      let(:test_class) do
        Class.new(EnvSettings::Base) do
          var :min_value,
              type: :integer,
              default: 0

          var :max_value,
              type: :integer,
              default: 100,
              validates: {
                comparison: { greater_than: :min_value }
              }
        end
      end

      it "validates comparison between fields" do
        ENV["MIN_VALUE"] = "50"
        ENV["MAX_VALUE"] = "30"

        expect { test_class.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /Max value must be greater than 50/
        )
      end

      it "passes when comparison is valid" do
        ENV["MIN_VALUE"] = "10"
        ENV["MAX_VALUE"] = "50"
        expect { test_class.validate! }.not_to raise_error
      end
    end

    describe "exclusion validation" do
      let(:test_class) do
        Class.new(EnvSettings::Base) do
          var :username,
              type: :string,
              validates: {
                exclusion: { in: %w[admin root superuser] }
              }
        end
      end

      it "validates exclusion" do
        ENV["USERNAME"] = "admin"
        expect { test_class.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /Username is reserved/
        )
      end

      it "passes when value is not excluded" do
        ENV["USERNAME"] = "john"
        expect { test_class.validate! }.not_to raise_error
      end
    end

    describe "absence validation" do
      let(:test_class) do
        Class.new(EnvSettings::Base) do
          var :legacy_field,
              type: :string,
              validates: {
                absence: true
              }
        end
      end

      it "validates absence" do
        ENV["LEGACY_FIELD"] = "value"
        expect { test_class.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /Legacy field must be blank/
        )
      end

      it "passes when value is absent" do
        expect { test_class.validate! }.not_to raise_error
      end
    end

    describe "unified validation syntax" do
      let(:test_class) do
        Class.new(EnvSettings::Base) do
          var :username,
              validates: {
                presence: true,
                length: { minimum: 3, maximum: 20 }
              }

          var :email,
              validates: {
                presence: true,
                format: { with: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i }
              }

          var :environment,
              validates: {
                inclusion: { in: %w[development test production] }
              }
        end
      end

      it "validates presence" do
        expect { test_class.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /Username can't be blank/
        )
      end

      it "validates length" do
        ENV["USERNAME"] = "ab"
        ENV["EMAIL"] = "test@example.com"

        expect { test_class.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /Username is too short/
        )
      end

      it "validates format" do
        ENV["USERNAME"] = "john"
        ENV["EMAIL"] = "invalid-email"

        expect { test_class.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /Email is invalid/
        )
      end

      it "validates inclusion" do
        ENV["USERNAME"] = "john"
        ENV["EMAIL"] = "test@example.com"
        ENV["ENVIRONMENT"] = "staging"

        expect { test_class.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /Environment is not included in the list/
        )
      end

      it "passes when all validations are valid" do
        ENV["USERNAME"] = "john"
        ENV["EMAIL"] = "test@example.com"
        ENV["ENVIRONMENT"] = "production"

        expect { test_class.validate! }.not_to raise_error
      end
    end

    describe "mixed ActiveModel and custom validations" do
      let(:test_class) do
        Class.new(EnvSettings::Base) do
          # ActiveModel numericality
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

          # Simple presence (converted to ActiveModel)
          var :database_url,
              type: :string,
              validates: { presence: true }
        end
      end

      it "validates both ActiveModel and converted validations" do
        ENV["PORT"] = "70000"
        expect { test_class.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /Port must be less than 65536/
        )
      end

      it "validates converted presence" do
        ENV["PORT"] = "3000"
        expect { test_class.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /Database url can't be blank/
        )
      end

      it "passes when all validations are valid" do
        ENV["PORT"] = "5000"
        ENV["DATABASE_URL"] = "postgresql://localhost/db"
        expect { test_class.validate! }.not_to raise_error
      end
    end

    describe "custom validator" do
      before do
        # Define custom validator
        stub_const("UrlValidator", Class.new(ActiveModel::EachValidator) do
          def validate_each(record, attribute, value)
            unless value =~ /\Ahttps?:\/\//
              record.errors.add(attribute, "must be a valid URL starting with http:// or https://")
            end
          end
        end)
      end

      let(:test_class) do
        Class.new(EnvSettings::Base) do
          var :api_endpoint,
              type: :string,
              validates: { url: true }
        end
      end

      it "uses custom validator" do
        ENV["API_ENDPOINT"] = "invalid-url"
        expect { test_class.validate! }.to raise_error(
          EnvSettings::ValidationError,
          /must be a valid URL/
        )
      end

      it "passes with valid URL" do
        ENV["API_ENDPOINT"] = "https://api.example.com"
        expect { test_class.validate! }.not_to raise_error
      end
    end
  end

  describe "error messages" do
    let(:test_class) do
      Class.new(EnvSettings::Base) do
        var :username,
            validates: {
              presence: true,
              length: { minimum: 3 }
            }

        var :age,
            type: :integer,
            validates: {
              numericality: { greater_than: 0 }
            }
      end
    end

    it "combines multiple validation errors" do
      ENV["AGE"] = "0"

      expect { test_class.validate! }.to raise_error(EnvSettings::ValidationError) do |error|
        expect(error.message).to include("Username can't be blank")
        expect(error.message).to include("Age must be greater than 0")
      end
    end
  end
end
