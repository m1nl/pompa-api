require 'pompa/authentication/token'

module Pompa
  module Authentication
    AuthenticationError = Class.new(StandardError)
    AccessError = Class.new(StandardError)
    ManipulationError = Class.new(StandardError)
  end
end
