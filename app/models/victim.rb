require 'base64'

class Victim < ApplicationRecord
  include Defaults
  include WorkerModel
  include Pageable
  include Model
  include NullifyBlanks

  SEND = 'send'.freeze
  RESET = 'reset'.freeze

  PENDING = 'pending'.freeze
  QUEUED = 'queued'.freeze
  SENT = 'sent'.freeze
  ERROR = 'error'.freeze

  FEMALE = 'female'.freeze
  MALE = 'male'.freeze

  CID_URI_REGEX = /(?<=[\'"]cid:)[^\'"]+(?=[\'"])/.freeze

  STATE_ORDER = { ERROR => 0, QUEUED => 1, SENT => 2, PENDING => 3 }.freeze

  RESOURCE = 'resource'.freeze
  EXTENSION = 'extension'.freeze
  CONTENT_TYPE = 'content_type'.freeze
  ATTACHMENT = 'attachment'.freeze
  FILENAME = 'filename'.freeze
  TEMPLATE = 'template'.freeze
  SUBJECT = 'subject'.freeze
  PLAINTEXT = 'plaintext'.freeze
  HTML = 'html'.freeze

  STATE_CHANGE = 'state_change'.freeze

  belongs_to :scenario, required: true
  belongs_to :target, required: false
  has_many :events
  has_one :report, foreign_key: 'victim_id',
    class_name: 'VictimReport'
  has_one :quicksearch, foreign_key: 'victim_id',
    class_name: 'VictimQuicksearch'

  validates :first_name, :last_name, :email, :code, :state, :state_order,
    :error_count, presence: true
  validates :email, format: { with: /@/, message: 'provide a valid email' }
  validates :gender, inclusion: { in: [FEMALE, MALE, nil] }
  validates :state, inclusion: { in: [PENDING, QUEUED, SENT, ERROR] }

  nullify_blanks :gender, :department, :comment

  default :state, PENDING
  default :code, proc { Pompa::Utils.random_code }
  default :error_count, 0

  scope :pending, -> { where(state: PENDING) }
  scope :queued, -> { where(state: QUEUED) }
  scope :sent, -> { where(state: SENT) }
  scope :error, -> { where(state: ERROR) }

  scope :quicksearch, ->(term) { joins(:quicksearch)
    .merge(VictimQuicksearch.search(term)) }

  worker_auto spawn: true
  worker_finished -> { state == PENDING || state == SENT || state == ERROR }

  build_model_append :scenario

  after_initialize :state_order
  before_validation :state_order

  def state_order
    self[:state_order] = STATE_ORDER[state]
  end

  def state_order=
    raise ArgumentError.new('Read-only attribute')
  end

  def state=(value)
    self[:state_order] = STATE_ORDER[value]
    super(value)
  end

  def display_name
    "#{first_name} #{last_name}"
  end

  def attachments(model = {}, opts = {})
    full_model = build_model(model, opts)

    attachments = []

    template = scenario.template
    html = full_model.dig(TEMPLATE, HTML)

    if !html.blank?
      inline_cids = html.scan(CID_URI_REGEX).uniq

      template.resources.joins(:template).includes(:template)
        .where(code: inline_cids).each do |r|
        m = r.build_model(full_model)
        attachments << {
          :filename => r.code + m.dig(RESOURCE, EXTENSION),
          :content_id => r.code,
          :content => Base64.strict_encode64(r.render(m, opts)),
          :content_type => m.dig(RESOURCE, CONTENT_TYPE),
          :inline => true,
        }
      end
    end

    template.attachments.joins(:resource).includes(:resource)
      .each do |a|
      m = a.build_model(full_model)
      attachments << {
        :filename => m.dig(ATTACHMENT, FILENAME),
        :content => Base64.strict_encode64(a.resource.render(m)),
        :content_type => m.dig(RESOURCE, CONTENT_TYPE),
        :inline => false,
      }
    end

    return attachments
  end

  def content(model = {}, opts = {})
    full_model = build_model(model, opts)

    return {
      :plaintext => full_model.dig(TEMPLATE, PLAINTEXT),
      :html => full_model.dig(TEMPLATE, HTML),
      :attachments => attachments(full_model),
    }
  end

  def mail(model = {}, opts = {})
    @expose_header ||= Rails.configuration.pompa.victim.expose_header

    full_model = build_model(model, opts)

    template = scenario.template

    headers = opts[:headers] || {}
    headers[@expose_header] ||= code if !@expose_header.blank?

    return {
      :sender_email => template.sender_email,
      :sender_name => template.sender_name,
      :recipient_email => email,
      :recipient_name => display_name,
      :subject => full_model.dig(TEMPLATE, SUBJECT),
      :headers => headers,
    }.merge!(content(full_model))
  end

  def send_email(opts = {})
    message({ :action => SEND, :force => !!opts.delete(:force) }, opts)
  end

  def reset_state(opts = {})
    message({ :action => RESET, :force => !!opts.delete(:force) }, opts)
  end

  def summary
    [id, first_name, last_name, gender, department, email, comment, code,
     state, last_error, error_count, sent_date, report.total_score,
     report.max_score]
  end

  def serialize_model!(name, model, opts)
    model[name].merge!(
      VictimSerializer.new(self).serializable_hash(:include => [])
        .except(*[:links]).deep_stringify_keys
    )
  end

  class << self
    def id_by_code(victim_code)
      Pompa::Cache.fetch("victim_#{victim_code}/id") do
        Victim.where(code: victim_code).pick(:id)
      end
    end

    def campaign_id_by_code(victim_code)
      Pompa::Cache.fetch("victim_#{victim_code}/campaign_id") do
        Campaign.joins(scenarios: :victims)
          .where(victims: { code: victim_code },
            state: [Campaign::STARTED, Campaign::PAUSED]).pick(:id)
      end
    end

    def template_id_by_code(victim_code)
      Pompa::Cache.fetch("victim_#{victim_code}/template_id") do
        Template.joins(scenarios: :victims)
          .where(victims: { code: victim_code }).pick(:id)
      end
    end

    def summary_header
      [:id, :first_name, :last_name, :gender, :department, :email, :comment,
       :code, :state, :last_error, :error_count, :sent_date, :total_score,
       :max_score]
    end
  end
end
