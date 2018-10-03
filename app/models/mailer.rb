class Mailer < ApplicationRecord
  include WorkerModel
  include Pageable
  include NullifyBlanks

  QUEUED = 'queued'.freeze
  SENT = 'sent'.freeze

  validates :name, :host, :port, presence: true
  validates :sender_email,
    format: { with: /@/, message: 'provide a valid email' }, allow_blank: true

  nullify_blanks :username, :password, :sender_email, :sender_name

  attr_encrypted :password,
    key: [Rails.application.secrets.database_key].pack('H*'),
    algorithm: 'aes-256-gcm', mode: :per_attribute_iv

  worker_auto start: true, spawn: true
end
