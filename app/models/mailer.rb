class Mailer < ApplicationRecord
  include WorkerModel
  include Pageable
  include NullifyBlanks
  include Defaults

  QUEUED = 'queued'.freeze
  SENT = 'sent'.freeze

  validates :name, :host, presence: true
  validates :port, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :sender_email,
    format: { with: /@/, message: 'provide a valid email' }, allow_blank: true
  validates :per_minute, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :burst, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  validate :password_check

  nullify_blanks :username, :password, :sender_email, :sender_name

  default :port, 587

  if !Rails.application.secrets.database_key.blank?
    attr_encrypted :password,
      key: [Rails.application.secrets.database_key].pack('H*'),
      algorithm: 'aes-256-gcm', mode: :per_attribute_iv
  else
    attribute :password
  end

  worker_auto start: true, spawn: true

  class << self
    def extra_headers
      @extra_headers if @extra_headers.nil?

      @extra_headers = {}
      Rails.configuration.pompa.mailer.extra_headers.each do |h|
        @extra_headers[h.name] = h.value || ''
      end

      @extra_headers
    end
  end

  private
    def password_check
      return if !Rails.application.secrets.database_key.blank?

      errors.add(:password,
        'unable to store password - database secret is blank') if !password.blank?
    end
end
