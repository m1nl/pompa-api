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

  nullify_blanks :username, :password, :sender_email, :sender_name

  if !Rails.application.credentials.active_record_encryption.blank?
    encrypts :password
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
end
