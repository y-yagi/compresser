# frozen_string_literal: true

module GemWithSend
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
end
