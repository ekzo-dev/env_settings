# frozen_string_literal: true

module EnvSettings
  class Error < StandardError; end
  class ValidationError < Error; end
  class ReadOnlyError < Error; end

  class Base
    class << self
      def env(name, type: :string, default: nil, validates: nil, reader: nil, writer: nil)
        env_key = name.to_s.upcase

        settings[name] = {
          type: type,
          default: default,
          validates: validates,
          env_key: env_key,
          reader: reader,
          writer: writer
        }

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
          raw_value = setting[:reader].call(setting[:env_key], setting)
        elsif get_default_reader
          raw_value = get_default_reader.call(setting[:env_key], setting)
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

        # Use custom writer if provided
        if setting[:writer]
          setting[:writer].call(setting[:env_key], value, setting)
        elsif get_default_writer
          get_default_writer.call(setting[:env_key], value, setting)
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

      def validate!
        settings.each do |name, config|
          next unless config[:validates]

          value = get_value(name)
          validators = config[:validates]

          # Presence validation
          if validators[:presence] && (value.nil? || value.to_s.empty?)
            raise ValidationError, "#{name} is required but not set"
          end

          # Length validation
          if validators[:length] && value
            length = value.to_s.length

            if validators[:length][:minimum] && length < validators[:length][:minimum]
              raise ValidationError, "#{name} is too short (minimum is #{validators[:length][:minimum]})"
            end

            if validators[:length][:maximum] && length > validators[:length][:maximum]
              raise ValidationError, "#{name} is too long (maximum is #{validators[:length][:maximum]})"
            end

            if validators[:length][:in] && !validators[:length][:in].include?(length)
              raise ValidationError, "#{name} length must be in range #{validators[:length][:in]}"
            end
          end

          # Format validation (regex)
          if validators[:format] && value
            unless value.to_s.match?(validators[:format])
              raise ValidationError, "#{name} has invalid format"
            end
          end

          # Inclusion validation
          if validators[:inclusion] && value
            unless validators[:inclusion].include?(value)
              raise ValidationError, "#{name} must be one of: #{validators[:inclusion].join(', ')}"
            end
          end
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
