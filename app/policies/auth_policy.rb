class AuthPolicy < ApplicationPolicy
  def token?
    @user.has_role?(User::Roles::AUTH)
  end
end
