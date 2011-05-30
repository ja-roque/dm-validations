require 'dm-core'
require 'dm-validations/support/ordered_hash'

class Object
  # If receiver is callable, calls it and
  # returns result. If not, just returns receiver
  # itself
  #
  # @return [Object]
  def try_call(*args)
    if self.respond_to?(:call)
      self.call(*args)
    else
      self
    end
  end
end

module DataMapper
  class Property
    def self.new(model, name, options = {})
      property = super
      property.model.auto_generate_validations(property)

      # FIXME: explicit return needed for YARD to parse this properly
      return property
    end
  end
end

require 'dm-validations/exceptions'
require 'dm-validations/validation_errors'
require 'dm-validations/contextual_validators'
require 'dm-validations/auto_validate'

require 'dm-validations/validators/generic_validator'
require 'dm-validations/validators/required_field_validator'
require 'dm-validations/validators/primitive_validator'
require 'dm-validations/validators/absent_field_validator'
require 'dm-validations/validators/confirmation_validator'
require 'dm-validations/validators/format_validator'
require 'dm-validations/validators/length_validator'
require 'dm-validations/validators/within_validator'
require 'dm-validations/validators/numeric_validator'
require 'dm-validations/validators/method_validator'
require 'dm-validations/validators/block_validator'
require 'dm-validations/validators/uniqueness_validator'
require 'dm-validations/validators/acceptance_validator'

require 'dm-validations/support/context'
require 'dm-validations/support/object'

module DataMapper
  module Validations

    Model.append_inclusions self

    extend Chainable

    def self.included(model)
      model.extend ClassMethods
    end

    # Ensures the object is valid for the context provided, and otherwise
    # throws :halt and returns false.
    #
    chainable do
      def save(context = default_validation_context)
        validation_context(context) { super() }
      end
    end

    chainable do
      def update(attributes = {}, context = default_validation_context)
        validation_context(context) { super(attributes) }
      end
    end

    chainable do
      def save_self(*)
        return false unless !dirty_self? || validation_context_stack.empty? || valid?(current_validation_context)
        super
      end
    end

    # Return the ValidationErrors
    #
    def errors
      @errors ||= ValidationErrors.new(self)
    end

    # Mark this resource as validatable. When we validate associations of a
    # resource we can check if they respond to validatable? before trying to
    # recursivly validate them
    #
    def validatable?
      true
    end

    # Alias for valid?(:default)
    #
    def valid_for_default?
      valid?(:default)
    end

    # Check if a resource is valid in a given context
    #
    def valid?(context = :default)
      klass = respond_to?(:model) ? model : self.class
      klass.validators.execute(context, self)
    end

    def validation_property_value(name)
      __send__(name) if respond_to?(name, true)
    end

    module ClassMethods
      include DataMapper::Validations::ValidatesPresence
      include DataMapper::Validations::ValidatesAbsence
      include DataMapper::Validations::ValidatesConfirmation
      include DataMapper::Validations::ValidatesPrimitiveType
      include DataMapper::Validations::ValidatesAcceptance
      include DataMapper::Validations::ValidatesFormat
      include DataMapper::Validations::ValidatesLength
      include DataMapper::Validations::ValidatesWithin
      include DataMapper::Validations::ValidatesNumericality
      include DataMapper::Validations::ValidatesWithMethod
      include DataMapper::Validations::ValidatesWithBlock
      include DataMapper::Validations::ValidatesUniqueness
      include DataMapper::Validations::AutoValidations

      # Return the set of contextual validators or create a new one
      #
      def validators
        @validators ||= ContextualValidators.new(self)
      end

      def inherited(base)
        super
        validators.contexts.each do |context, validators|
          base.validators.context(context).concat(validators)
        end
      end

      def create(attributes = {}, *args)
        resource = new(attributes)
        resource.save(*args)
        resource
      end

      private

      # Given a new context create an instance method of
      # valid_for_<context>? which simply calls valid?(context)
      # if it does not already exist
      #
      def self.create_context_instance_methods(model, context)
        # TODO: deprecate `valid_for_#{context}?`
        # what's wrong with requiring the caller to pass the context as an arg?
        #   eg, `valid?(:context)`
        context = context.to_sym

        name = "valid_for_#{context}?"
        present = model.respond_to?(:resource_method_defined) ? model.resource_method_defined?(name) : model.instance_methods.include?(name)
        unless present
          model.class_eval <<-RUBY, __FILE__, __LINE__ + 1
            def #{name}                         # def valid_for_signup?
              valid?(#{context.inspect})        #   valid?(:signup)
            end                                 # end
          RUBY
        end
      end

    end # module ClassMethods
  end # module Validations

  # Provide a const alias for backward compatibility with plugins
  # This is scheduled to go away though, definitely before 1.0
  Validate = Validations

end # module DataMapper
