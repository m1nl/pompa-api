class AuthPolicy < ApplicationPolicy
  def token?
    return true
  end
end
