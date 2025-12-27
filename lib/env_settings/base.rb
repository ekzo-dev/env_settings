# frozen_string_literal: true

begin
  require "active_model"
rescue LoadError
  # ActiveModel is optional
end

module EnvSettings
  class Error < StandardError; end
  class ValidationError < Error; end
  class ReadOnlyError < Error; end

  class Base
    class << self
      def var(name, type: :string, default: nil, validates: nil, reader: nil, writer: nil)
        env_key = name.to_s.upcase

        settings[name] = {
          type: type,
          default: default,
          validates: validates,
          env_key: env_key,
          reader: reader,
          writer: writer
        }

        # Register ActiveModel validations if available
        if defined?(ActiveModel::Validations) && validates
          ensure_validator_class!
          validator_class.add_attribute(name, self)
          # Always use ActiveModel if available
          validator_class.validates name, **validates if validates.is_a?(Hash)
        end

        define_singleton_method(name) do
          get_value(name)
        end

        define_singleton_method("#{name}=") do |value|
          set_value(name, value)
        end

        # Define boolean helper method for boolean types
        if type == :boolean
          define_singleton_method("#{name}?") do
            !!get_value(name)
          end
        end

        # Define presence check
        define_singleton_method("#{name}_present?") do
          value = get_value(name)
          !value.nil? && value != ""
        end
      end

      def settings
        @settings ||= {}
      end

      def validator_class
        @validator_class
      end

      def ensure_validator_class!
        return if @validator_class

        parent_class = self
        @validator_class = Class.new do
          include ActiveModel::Validations if defined?(ActiveModel::Validations)
          include ActiveModel::Model if defined?(ActiveModel::Model)

          # Define methods for reading values
          parent_class.settings.keys.each do |key|
            define_method(key) do
              # Check if value is set on instance, otherwise read from parent
              ivar = "@#{key}"
              if instance_variable_defined?(ivar)
                instance_variable_get(ivar)
              else
                parent_class.get_value(key)
              end
            end

            define_method("#{key}=") do |value|
              instance_variable_set("@#{key}", value)
            end
          end

          # Method to add new vars
          def self.add_attribute(name, parent_class)
            define_method(name) do
              ivar = "@#{name}"
              if instance_variable_defined?(ivar)
                instance_variable_get(ivar)
              else
                parent_class.get_value(name)
              end
            end

            define_method("#{name}=") do |value|
              instance_variable_set("@#{name}", value)
            end
          end

          # For ActiveModel error messages
          def self.model_name
            ActiveModel::Name.new(self, nil, "EnvSettings")
          end
        end
      end

      def default_reader(callable = nil, &block)
        @default_reader = callable || block
      end

      def default_writer(callable = nil, &block)
        @default_writer = callable || block
      end

      def get_default_reader
        @default_reader
      end

      def get_default_writer
        @default_writer
      end

      def get_value(name)
        setting = settings[name]
        return nil unless setting

        # Use custom reader if provided
        if setting[:reader]
          raw_value = setting[:reader].call(setting)
        elsif get_default_reader
          raw_value = get_default_reader.call(setting)
        else
          # Default behavior: read from ENV
          raw_value = ENV[setting[:env_key]]
        end

        if raw_value.nil?
          return setting[:default]
        end

        coerce_value(raw_value, setting[:type])
      end

      def set_value(name, value)
        setting = settings[name]
        return unless setting

        # Validate before writing if validations are defined
        validate_var!(name, value) if setting[:validates]

        # Use custom writer if provided
        if setting[:writer]
          setting[:writer].call(value, setting)
        elsif get_default_writer
          get_default_writer.call(value, setting)
        else
          # Default behavior: raise error (read-only)
          raise ReadOnlyError, "Cannot write to '#{name}': variable is read-only. Provide a writer callback to enable writing."
        end
      end

      def coerce_value(value, type)
        case type
        when :string
          value.to_s
        when :integer
          value.to_i
        when :float
          value.to_f
        when :boolean
          %w[true 1 yes on].include?(value.to_s.downcase)
        when :array
          parse_array(value)
        when :hash
          parse_hash(value)
        when :symbol
          value.to_sym
        else
          value
        end
      end

      def parse_array(value)
        return [] if value.nil? || value.empty?

        # Try to parse as JSON first
        begin
          parsed = JSON.parse(value)
          return parsed if parsed.is_a?(Array)
        rescue JSON::ParserError
          # Fall back to comma-separated
        end

        value.split(',').map(&:strip)
      end

      def parse_hash(value)
        return {} if value.nil? || value.empty?

        begin
          parsed = JSON.parse(value)
          return parsed if parsed.is_a?(Hash)
        rescue JSON::ParserError
          {}
        end
      end

      def validate_var!(name, value)
        setting = settings[name]
        return unless setting && setting[:validates]

        validators = setting[:validates]

        # Use ActiveModel validations if available
        if defined?(ActiveModel::Validations) && validator_class
          # Use existing validator_class for full validation context
          instance = validator_class.new

          # Set the value being validated
          instance.send("#{name}=", value)

          # Validate only the specified attribute (Rails 7.1+)
          if instance.respond_to?(:validate)
            instance.validate(name)
          else
            instance.valid?
          end

          attribute_errors = instance.errors[name]

          if attribute_errors.any?
            raise ValidationError, "#{name.to_s.capitalize.gsub('_', ' ')} #{attribute_errors.join(', ')}"
          end
          return
        end

        # Run simple validations (when ActiveModel is not available)
        # Presence validation
        if validators[:presence] && (value.nil? || value.to_s.empty?)
          raise ValidationError, "#{name.to_s.capitalize.gsub('_', ' ')} can't be blank"
        end

        # Length validation
        if validators[:length] && value
          length_opts = validators[:length]
          length = value.to_s.length

          if length_opts[:minimum] && length < length_opts[:minimum]
            raise ValidationError, "#{name.to_s.capitalize.gsub('_', ' ')} is too short (minimum is #{length_opts[:minimum]} characters)"
          end

          if length_opts[:maximum] && length > length_opts[:maximum]
            raise ValidationError, "#{name.to_s.capitalize.gsub('_', ' ')} is too long (maximum is #{length_opts[:maximum]} characters)"
          end

          if length_opts[:in] && !length_opts[:in].include?(length)
            raise ValidationError, "#{name.to_s.capitalize.gsub('_', ' ')} is the wrong length (should be #{length_opts[:in]} characters)"
          end
        end

        # Format validation
        if validators[:format] && value
          format_opts = validators[:format]
          format_regex = format_opts.is_a?(Hash) ? format_opts[:with] : format_opts
          unless value.to_s.match?(format_regex)
            message = format_opts.is_a?(Hash) && format_opts[:message] ? format_opts[:message] : "is invalid"
            raise ValidationError, "#{name.to_s.capitalize.gsub('_', ' ')} #{message}"
          end
        end

        # Inclusion validation
        if validators[:inclusion] && value
          inclusion_opts = validators[:inclusion]
          inclusion_values = inclusion_opts.is_a?(Hash) ? inclusion_opts[:in] : inclusion_opts
          unless inclusion_values.include?(value)
            raise ValidationError, "#{name.to_s.capitalize.gsub('_', ' ')} is not included in the list"
          end
        end
      end

      def validate!
        # Use ActiveModel validations if available
        if defined?(ActiveModel::Validations) && validator_class
          instance = validator_class.new
          unless instance.valid?
            errors = instance.errors.full_messages.join(", ")
            raise ValidationError, errors
          end
        end

        # Run simple validations (when ActiveModel is not available)
        settings.each do |name, config|
          next unless config[:validates]
          validate_var!(name, get_value(name))
        end
      end

      def all
        settings.keys.each_with_object({}) do |name, hash|
          hash[name] = get_value(name)
        end
      end

      def to_h
        all
      end
    end
  end
end
