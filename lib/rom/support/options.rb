module ROM
  # Helper module for classes with a constructor accepting option hash
  #
  # This allows us to DRY up code as option hash is a very common pattern used
  # across the codebase. It is an internal implementation detail not meant to
  # be used outside of ROM
  #
  # @example
  #   class User
  #     include Options
  #
  #     option :name, type: String, reader: true
  #     option :admin, allow: [true, false], reader: true, default: false
  #
  #     def initialize(options={})
  #       super
  #     end
  #   end
  #
  #   user = User.new(name: 'Piotr')
  #   user.name # => "Piotr"
  #   user.admin # => false
  #
  # @api public
  module Options
    # @return [Hash<Option>] Option definitions
    #
    # @api public
    attr_reader :options

    def self.included(klass)
      klass.extend ClassMethods
      klass.option_definitions = Definitions.new
    end

    # Defines a single option
    #
    # @api private
    class Option
      attr_reader :name, :type, :allow, :default

      def initialize(name, options = {})
        @name = name
        @type = options.fetch(:type) { Object }
        @reader = options.fetch(:reader) { false }
        @allow = options.fetch(:allow) { [] }
        @default = options.fetch(:default) { Undefined }
        @ivar = :"@#{name}" if @reader
      end

      def reader?
        @reader
      end

      def assign_reader_value(object, value)
        object.instance_variable_set(@ivar, value)
      end

      def default?
        @default != Undefined
      end

      def default_value(object)
        default.is_a?(Proc) ? default.call(object) : default
      end

      def type_matches?(value)
        value.is_a?(type)
      end

      def allow?(value)
        allow.empty? || allow.include?(value)
      end
    end

    # Manage all available options
    #
    # @api private
    class Definitions
      def initialize
        @options = {}
      end

      def initialize_copy(source)
        super
        @options = @options.dup
      end

      def define(option)
        @options[option.name] = option
      end

      def process(object, options)
        ensure_known_options(options)

        each do |name, option|
          if option.default? && !options.key?(name)
            options[name] = option.default_value(object)
          end

          if options.key?(name)
            validate_option_value(option, name, options[name])
          end

          option.assign_reader_value(object, options[name]) if option.reader?
        end
      end

      def names
        @options.keys
      end

      private

      def each(&block)
        @options.each(&block)
      end

      def ensure_known_options(options)
        options.each_key do |name|
          @options.fetch(name) do
            raise InvalidOptionKeyError,
              "#{name.inspect} is not a valid option"
          end
        end
      end

      def validate_option_value(option, name, value)
        unless option.type_matches?(value)
          raise InvalidOptionValueError,
            "#{name.inspect}:#{value.inspect} has incorrect type"
        end

        unless option.allow?(value)
          raise InvalidOptionValueError,
            "#{name.inspect}:#{value.inspect} has incorrect value"
        end
      end
    end

    # @api private
    module ClassMethods
      # Available options
      #
      # @return [Definitions]
      #
      # @api private
      attr_accessor :option_definitions

      # Defines an option
      #
      # @param [Symbol] name option name
      #
      # @param [Hash] settings option settings
      # @option settings [Class] :type Restrict option type. Default: +Object+
      # @option settings [Boolean] :reader Define a reader? Default: +false+
      # @option settings [Array] :allow Allow certain values. Default: Allow anything
      # @option settings [Object] :default Set default value for missing option
      #
      # @api public
      def option(name, settings = {})
        option = Option.new(name, settings)
        option_definitions.define(option)
        attr_reader(name) if option.reader?
      end

      # @api private
      def inherited(descendant)
        descendant.option_definitions = option_definitions.dup
        super
      end
    end

    # Initialize options provided as optional last argument hash
    #
    # @example
    #   class Commands
    #     include Options
    #
    #     # ...
    #
    #     def initialize(relations, options={})
    #       @relation = relation
    #       super
    #     end
    #   end
    #
    # @param [Array] args
    def initialize(*args)
      options = args.last ? args.last.dup : {}
      self.class.option_definitions.process(self, options)
      @options = options.freeze
    end
  end
end
