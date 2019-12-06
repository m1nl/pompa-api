require 'pompa/authentication/token'

module Pompa
  module Authentication
    Error = Class.new(StandardError)
    AccessError = Class.new(Error)
    AuthenticationError = Class.new(Error)
    ManipulationError = Class.new(Error)
  end
end
