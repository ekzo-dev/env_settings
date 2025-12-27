# frozen_string_literal: true

require "spec_helper"

RSpec.describe EnvSettings::Base, "validation on write" do
  before do
    ENV.clear
  end

  describe "simple validations on write" do
    let(:storage) { {} }

    let(:test_class) do
      test_storage = storage
      Class.new(EnvSettings::Base) do
        var :username,
            type: :string,
            validates: { presence: true, length: { minimum: 3, maximum: 20 } },
            writer: ->(value, setting) { test_storage[setting[:env_key]] = value }

        var :email,
            type: :string,
            validates: { format: { with: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i } },
            writer: ->(value, setting) { test_storage[setting[:env_key]] = value }

        var :role,
            type: :string,
            validates: { inclusion: { in: %w[admin user guest] } },
            writer: ->(value, setting) { test_storage[setting[:env_key]] = value }
      end
    end

    context "presence validation" do
      it "raises error when assigning nil" do
        expect { test_class.username = nil }.to raise_error(
          EnvSettings::ValidationError,
          /can't be blank/
        )
      end

      it "raises error when assigning empty string" do
        expect { test_class.username = "" }.to raise_error(
          EnvSettings::ValidationError,
          /can't be blank/
        )
      end

      it "allows valid value" do
        expect { test_class.username = "john" }.not_to raise_error
        expect(storage["USERNAME"]).to eq("john")
      end

      it "does not write invalid value to storage" do
        expect { test_class.username = nil }.to raise_error(EnvSettings::ValidationError)
        expect(storage["USERNAME"]).to be_nil
      end
    end

    context "length validation" do
      it "raises error when value too short" do
        expect { test_class.username = "ab" }.to raise_error(
          EnvSettings::ValidationError,
          /too short/
        )
      end

      it "raises error when value too long" do
        expect { test_class.username = "a" * 21 }.to raise_error(
          EnvSettings::ValidationError,
          /too long/
        )
      end

      it "allows value within range" do
        expect { test_class.username = "john" }.not_to raise_error
        expect(storage["USERNAME"]).to eq("john")
      end
    end

    context "format validation" do
      it "raises error for invalid format" do
        expect { test_class.email = "invalid-email" }.to raise_error(
          EnvSettings::ValidationError,
          /is invalid/
        )
      end

      it "allows valid format" do
        expect { test_class.email = "user@example.com" }.not_to raise_error
        expect(storage["EMAIL"]).to eq("user@example.com")
      end
    end

    context "inclusion validation" do
      it "raises error for value not in list" do
        expect { test_class.role = "superadmin" }.to raise_error(
          EnvSettings::ValidationError,
          /not included in the list/
        )
      end

      it "allows value in list" do
        expect { test_class.role = "admin" }.not_to raise_error
        expect(storage["ROLE"]).to eq("admin")
      end
    end
  end

  describe "ActiveModel validations on write" do
    let(:storage) { {} }

    let(:test_class) do
      test_storage = storage
      Class.new(EnvSettings::Base) do
        var :age,
            type: :integer,
            validates: { numericality: { greater_than: 0, less_than: 150 } },
            writer: ->(value, setting) { test_storage[setting[:env_key]] = value }

        var :score,
            type: :integer,
            validates: { numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 } },
            writer: ->(value, setting) { test_storage[setting[:env_key]] = value }
      end
    end

    it "validates numericality on write" do
      skip "ActiveModel not available" unless defined?(ActiveModel::Validations)

      expect { test_class.age = -5 }.to raise_error(
        EnvSettings::ValidationError,
        /must be greater than 0/
      )
    end

    it "allows valid numeric value" do
      skip "ActiveModel not available" unless defined?(ActiveModel::Validations)

      expect { test_class.age = 25 }.not_to raise_error
      expect(storage["AGE"]).to eq(25)
    end

    it "validates range on write" do
      skip "ActiveModel not available" unless defined?(ActiveModel::Validations)

      expect { test_class.score = 150 }.to raise_error(
        EnvSettings::ValidationError,
        /must be less than or equal to 100/
      )
    end
  end

  describe "no validation without validates option" do
    let(:storage) { {} }

    let(:test_class) do
      test_storage = storage
      Class.new(EnvSettings::Base) do
        var :free_text,
            type: :string,
            writer: ->(value, setting) { test_storage[setting[:env_key]] = value }
      end
    end

    it "allows any value when no validation defined" do
      expect { test_class.free_text = nil }.not_to raise_error
      expect { test_class.free_text = "" }.not_to raise_error
      expect { test_class.free_text = "anything" }.not_to raise_error
    end
  end

  describe "validation with default_writer" do
    let(:storage) { {} }

    let(:test_class) do
      test_storage = storage
      Class.new(EnvSettings::Base) do
        default_writer ->(value, setting) { test_storage[setting[:env_key]] = value }

        var :username,
            type: :string,
            validates: { presence: true, length: { minimum: 3 } }
      end
    end

    it "validates when using default_writer" do
      expect { test_class.username = "ab" }.to raise_error(
        EnvSettings::ValidationError,
        /too short/
      )
    end

    it "writes valid value with default_writer" do
      expect { test_class.username = "john" }.not_to raise_error
      expect(storage["USERNAME"]).to eq("john")
    end
  end
end
