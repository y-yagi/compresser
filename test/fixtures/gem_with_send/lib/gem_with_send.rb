# frozen_string_literal: true

module GemWithSend
  # --- static symbol send (already handled by resolve_static_send_calls) ---

  def self.static_send_underscore(parser, oth)
    parser.__send__(:convert_to_uri, oth)
  end

  def self.static_send_underscore_no_args(parser)
    parser.__send__(:to_s)
  end

  def self.static_public_send(obj, oth)
    obj.public_send(:process, oth)
  end

  def self.static_send(obj, oth)
    obj.send(:validate, oth)
  end

  def self.dynamic_variable(obj, method_name)
    obj.__send__(method_name)
  end

  def self.dynamic_string(obj, c)
    obj.__send__("#{c}=", 1)
  end

  # --- dynamic send over symbol array (handled by expand_dynamic_send_calls) ---

  class Component
    COMPONENTS = [:name, :value].freeze

    def name; @name; end
    def name=(v); @name = v; end
    def value; @value; end
    def value=(v); @value = v; end

    def component
      COMPONENTS
    end

    def component_ary
      component.collect do |x|
        self.__send__(x)
      end
    end

    def replace!(oth)
      component.each do |c|
        self.__send__("#{c}=", oth.__send__(c))
      end
    end
  end
end
