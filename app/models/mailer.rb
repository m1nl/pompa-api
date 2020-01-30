class Mailer < ApplicationRecord
  include WorkerModel
  include Pageable
  include NullifyBlanks

  QUEUED = 'queued'.freeze
  SENT = 'sent'.freeze

  validates :name, :host, presence: true
  validates :port, numericality: { only_integer: true, greater_than: 0 }
  validates :sender_email,
    format: { with: /@/, message: 'provide a valid email' }, allow_blank: true

  validate :password_check

  nullify_blanks :username, :password, :sender_email, :sender_name

  if !Rails.application.secrets.database_key.blank?
    attr_encrypted :password,
      key: [Rails.application.secrets.database_key].pack('H*'),
      algorithm: 'aes-256-gcm', mode: :per_attribute_iv
  else
    attribute :password
  end

  worker_auto start: true, spawn: true

  private
    def password_check
      return if !Rails.application.secrets.database_key.blank?

      errors.add(:password,
        'unable to store password - database secret is blank') if !password.blank?
    end
end
