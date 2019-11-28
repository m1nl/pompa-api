class User < ApplicationRecord

  class Roles
    AUTH='AUTH'.freeze
  end

  def has_role?(role)
    roles.include?(role)
  end
end
