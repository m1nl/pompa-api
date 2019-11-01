require 'pompa/authentication/token'

module Pompa
  module Authentication
    AuthenticationError = Class.new(StandardError)
    ValidationError = Class.new(StandardError)
  end
end
