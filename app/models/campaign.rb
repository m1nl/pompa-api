require 'oj'

class Campaign < ApplicationRecord
  include Defaults
  include Pageable
  include WorkerModel
  include Model

  CREATED = 'created'.freeze
  STARTED = 'started'.freeze
  PAUSED = 'paused'.freeze
  FINISHED = 'finished'.freeze

  START = 'start'.freeze
  PAUSE = 'pause'.freeze
  FINISH = 'finish'.freeze

  STATE_ORDER = { CREATED => 0, STARTED => 1, PAUSED => 2, FINISHED => 3 }.freeze

  STATE_CHANGE = 'state_change'.freeze

  has_many :scenarios

  validates :name, :state, :state_order, presence: true
  validates :state, inclusion: { in: [CREATED, STARTED, PAUSED, FINISHED] }

  validate :dates_check
  validate :state_check

  default :state, CREATED

  scope :created, -> { where(state: CREATED) }
  scope :started, -> { where(state: STARTED) }
  scope :paused, -> { where(state: PAUSED) }
  scope :finished, -> { where(state: FINISHED) }

  worker_auto start: true, spawn: true
  worker_finished -> { state == FINISHED }

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

  def start(opts = {})
    message({ :action => START }, opts.merge(:head => true))
  end

  def pause(opts = {})
    message({ :action => PAUSE }, opts.merge(:head => true))
  end

  def finish(opts = {})
    message({ :action => FINISH }, opts.merge(:head => true))
  end

  def push_event(victim_id, goal_id, data = {}, opts = {})
    self.class.push_event(id, victim_id, goal_id, data, opts)
  end

  def synchronize_events(opts = {})
    self.class.synchronize_events(id, opts)
  end

  class << self
    def push_event(campaign_id, victim_id, goal_id, data = {}, opts = {})
      Pompa::RedisConnection.redis(opts) do |r|
        event = {
          victim_id: victim_id,
          goal_id: goal_id,
          data: data,
          reported_date: Time.current,
        }

        r.rpush(event_queue_key_name(campaign_id), event.to_json)
      end
    end

    def synchronize_events(campaign_id, opts = {})
      ids = []
      key_name = event_queue_key_name(campaign_id)

      Pompa::RedisConnection.redis(opts) do |r|
        return ids unless r.llen(key_name) > 0

        ActiveRecord::Base.transaction do
          loop do
            result = r.multi do |m|
              m.lrange(key_name, 0, batch_size - 1)
              m.ltrim(key_name, batch_size, -1)
            end

            result = result[0]
            events = []

            result.each do |j|
              begin
                hash = Oj.load(j, symbol_keys: true)
                event = Event.new(hash)
                events << event
              rescue Oj::ParseError => e
              end
            end

            ids.concat Event.import(events, validate => true)[:ids]
            break if result.length < batch_size
          end
        end
      end

      return ids
    end

    def batch_size
      @batch_size ||= Rails.configuration.pompa.batch_size
    end

    def event_queue_key_name(id)
      "#{name}:#{id}:Events"
    end
  end

  def serialize_model!(name, model, opts)
    model[name].merge!(
      CampaignSerializer.new(self)
        .serializable_hash(:include => []).except(*[:links])
        .deep_stringify_keys
    )
  end

  private
    def dates_check
      if start_date_changed? && !start_date.nil?
        errors.add(:start_date,
          'campaign cannot start in the past') if start_date < Time.current
      end

      if finish_date_changed? && !finish_date.nil?
        errors.add(:finish_date,
          'campaign cannot finish in the past') if finish_date < Time.current
      end

      if (start_date_changed? || finish_date_changed?) &&
        !start_date.nil? && !finish_date.nil?
        errors.add(:finish_date,
          'campaign cannot finish before it starts') if finish_date <= start_date
      end
    end

    def state_check
      if state == FINISHED
        errors.add(:start_date,
          'unable to modify after campaign finishes') if start_date_changed?
        errors.add(:finish_date,
          'unable to modify after campaign finishes') if finish_date_changed?
      end

      if [STARTED, PAUSED].include?(state)
        errors.add(:start_date,
          'unable to modify after campaign starts') if start_date_changed?
      end
    end
end
