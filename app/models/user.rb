class User < ApplicationRecord
  before_validation :normalize_roles
  validate :roles_check

  class Roles
    AUTH = 'AUTH'.freeze

    def self.all
      return @all_roles if !@all_roles.nil?

      @all_roles = []
      constants.each do |c|
        @all_roles << const_get(c)
      end

      return @all_roles
    end
  end

  def has_role?(role)
    roles.include?(role)
  end

  def display_name
    "#{client_id}"
  end

  def to_s
    "#{display_name}"
  end

  private
    def normalize_roles
      roles ||= []
    end

    def roles_check
      return if !roles_changed?
      return if roles.blank?

      roles.each do |r|
        if !Roles.all.include?(r)
          errors.add(:roles,
            "invalid role #{r}")
        end
      end
   end
end
