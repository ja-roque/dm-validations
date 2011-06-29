module DataMapper
  # for options_with_message
  # TODO: rename :auto_validation => :infer_validation
  Property.accept_options :auto_validation, :validates, :set, :format, :message, :messages

  module Validations
    module Inferred

      module ModelExtension
        # @api private
        def property(*)
          property = super
          Validations::Inferred.generate_for_property(property)
          # FIXME: explicit return needed for YARD to parse this properly
          return property
        end
      end # module ModelExtension

      Model.append_extensions Inferred::ModelExtension


      # TODO: remove all the other @disabled_auto_validations reader methods
      # Checks whether auto validations are currently
      # disabled (see +disable_auto_validations+ method
      # that takes a block)
      #
      # @return [TrueClass, FalseClass]
      #   true if auto validation is currently disabled
      #
      # @api public
      def infer_validations?
        @infer_validations
      end

      # Disable generation of validations for the duration of the given block
      # 
      # @api public
      def without_inferred_validations
        previous, @infer_validations = @infer_validations, true
        yield
      ensure
        @infer_validations = previous
      end

      # Infer validations for a given property. This will only occur
      # if the option :auto_validation is either true or left undefined.
      #
      #   Triggers that generate validator creation
      #
      #   :required => true
      #       Setting the option :required to true causes a
      #       validates_presence_of validator to be created for the property
      #
      #   :length => 20
      #       Setting the option :length causes a validates_length_of
      #       validator to be created for the property. If the
      #       value is a Integer the validation will set :maximum => value
      #       if the value is a Range the validation will set
      #       :within => value
      #
      #   :format => :predefined / lambda / Proc
      #       Setting the :format option causes a validates_format_of
      #       validator to be created for the property
      #
      #   :set => ["foo", "bar", "baz"]
      #       Setting the :set option causes a validates_within
      #       validator to be created for the property
      #
      #   Integer type
      #       Using a Integer type causes a validates_numericality_of
      #       validator to be created for the property.  integer_only
      #       is set to true
      #
      #   BigDecimal or Float type
      #       Using a Integer type causes a validates_numericality_of
      #       validator to be created for the property.  integer_only
      #       is set to false, and precision/scale match the property
      #
      #
      #   Messages
      #
      #   :messages => {..}
      #       Setting :messages hash replaces standard error messages
      #       with custom ones. For instance:
      #       :messages => {:presence => "Field is required",
      #                     :format => "Field has invalid format"}
      #       Hash keys are: :presence, :format, :length, :is_unique,
      #                      :is_number, :is_primitive
      #
      #   :message => "Some message"
      #       It is just shortcut if only one validation option is set
      #
      # @api private
      def self.generate_for_property(property)
        return unless property.model.infer_validations? && property.auto_validation

        # all inferred validations (aside from Presence/Absence) should be skipped
        # validation when the value is nil
        opts = { :allow_nil => true }

        if property.options.key?(:validates)
          opts[:context] = property.options[:validates]
        end

        # TODO: update these methods to return an array of:
        #   [Validator::Abstract, attribute_name, validator_options]
        # Then iterate over *that* list and call:
        #   property.model.validators.add(*args)
        infer_presence_validation_for(property, opts.dup)
        infer_length_validation_for(property, opts.dup)
        infer_format_validation_for(property, opts.dup)
        infer_uniqueness_validation_for(property, opts.dup)
        infer_within_validation_for(property, opts.dup)
        infer_type_validation_for(property, opts.dup)
      end

    private

      # @api private
      def self.infer_presence_validation_for(property, options)
        return if property.allow_blank? || property.serial?

        validation_options = options_with_message(options, property, :presence)
        property.model.validates_presence_of property.name, validation_options
      end

      # @api private
      def self.infer_length_validation_for(property, options)
        return unless (property.kind_of?(Property::String) ||
                       property.kind_of?(Property::Text))

        length = property.options.fetch(:length, Property::String.length)

        if length.is_a?(Range)
          if length.last == Infinity
            raise ArgumentError, "Infinity is not a valid upper bound for a length range"
          end
          options[:within]  = length
        else
          options[:maximum] = length
        end

        validation_options = options_with_message(options, property, :length)
        property.model.validates_length_of property.name, validation_options
      end

      # @api private
      def self.infer_format_validation_for(property, options)
        return unless property.options.key?(:format)

        options[:with] = property.options[:format]

        validation_options = options_with_message(options, property, :format)
        property.model.validates_format_of property.name, validation_options
      end

      # @api private
      def self.infer_uniqueness_validation_for(property, options)
        return unless property.options.key?(:unique)

        case value = property.options[:unique]
          when Array, Symbol
            options[:scope] = Array(value)

            validation_options = options_with_message(options, property, :is_unique)
            property.model.validates_uniqueness_of property.name, validation_options
          when TrueClass
            validation_options = options_with_message(options, property, :is_unique)
            property.model.validates_uniqueness_of property.name, validation_options
        end
      end

      # @api private
      def self.infer_within_validation_for(property, options)
        return unless property.options.key?(:set)

        options[:set] = property.options[:set]

        validation_options = options_with_message(options, property, :within)
        property.model.validates_within property.name, validation_options
      end

      # @api private
      def self.infer_type_validation_for(property, options)
        return if property.respond_to?(:custom?) && property.custom?

        if property.kind_of?(Property::Numeric)
          options[:gte] = property.min if property.min
          options[:lte] = property.max if property.max
        end

        if Integer == property.primitive
          options[:integer_only] = true

          validation_options = options_with_message(options, property, :is_number)
          property.model.validates_numericality_of property.name, validation_options
        elsif (BigDecimal == property.primitive ||
               Float == property.primitive)
          options[:precision] = property.precision
          options[:scale]     = property.scale

          validation_options = options_with_message(options, property, :is_number)
          property.model.validates_numericality_of property.name, validation_options
        else
          # We only need this in the case we don't already
          # have a numeric validator, because otherwise
          # it will cause duplicate validation errors
          validation_options = options_with_message(options, property, :is_primitive)
          property.model.validates_primitive_type_of property.name, validation_options
        end
      end

      # adds message for validator
      # 
      # @api private
      def self.options_with_message(base_options, property, validator_name)
        options = base_options.clone
        opts    = property.options

        if opts.key?(:messages)
          options[:message] = opts[:messages][validator_name]
        elsif opts.key?(:message)
          options[:message] = opts[:message]
        end

        options
      end
    end # module Inferred
  end # module Validations
end # module DataMapper
