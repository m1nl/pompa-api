require 'csv'

class Scenario < ApplicationRecord
  include Pageable
  include Model

  COL_HIT = 'hit'.freeze
  COL_REPORTED_DATE = 'reported_date'.freeze
  COL_IP = 'ip'.freeze
  COL_USER_AGENT = 'user-agent'.freeze
  COL_COOKIE = 'cookie'.freeze
  COL_DATA = 'data'.freeze

  CSV_COLUMNS = [COL_HIT, COL_REPORTED_DATE, COL_IP,
    COL_USER_AGENT, COL_COOKIE, COL_DATA].freeze
  CSV_DATE_FORMAT = '%Y-%m-%d %H:%M:%S'.freeze

  belongs_to :campaign, required: true
  belongs_to :template, required: true
  belongs_to :mailer, required: true
  belongs_to :group
  has_many :victims
  has_one :report, foreign_key: 'scenario_id', class_name: 'ScenarioReport'

  validate :campaign_check

  after_commit :resync_campaign
  after_commit :synchronize_group, on: [:create, :update],
    if: :saved_change_to_group_id?

  build_model_append :campaign, :group, :template

  def synchronize_group
    ids = []

    if !valid?
      raise InvalidState
        .new('scenario is not valid')
    end

    if campaign.state == Campaign::FINISHED
      raise InvalidState
        .new('unable to synchronize group after campaign finishes')
    end

    victims.where(state: Victim::PENDING).delete_all
    return ids if group.nil?

    ActiveRecord::Base.transaction do
      loop do
        victims = []
        group.targets
          .where.not(id: Victim.select(:target_id).where(scenario_id: self.id)
            .where.not(target_id: nil))
          .take(batch_size).each do |t|
          victim = Victim.new(
            first_name: t.first_name,
            last_name: t.last_name,
            email: t.email,
            gender: t.gender,
            department: t.department,
            comment: t.comment,
            scenario: self,
            target: t,
          )
          victims << victim
        end

        ids.concat Victim.import(victims, :validate => true)[:ids]
        break if victims.length < batch_size
      end
    end

    campaign.ping if !campaign.nil?

    return ids
  end

  def resync_campaign
    ids = [campaign_id]
    ids << campaign_id_before_last_save if saved_change_to_campaign_id?

    ids.each do |c|
      campaign = Campaign.find_by_id(c)
      next if campaign.nil?

      campaign.with_worker_lock do
        campaign.resync
        campaign.pause if campaign.state == Campaign::STARTED
      end
    end
  end

  def victims_summary_csv
    Enumerator.new do |y|
      header = Victim.summary_header
      header.concat(
        template.goals.order(score: :desc, id: :asc).map { |g|
          CSV_COLUMNS.map { |p|
            "#{g.name.parameterize.underscore}_#{p.parameterize.underscore}"
          }
        }.flatten
      )
      y << CSV.generate_line(header)

      victims_summary.each do |r|
        y << CSV.generate_line(
          r.map { |c| c.is_a?(Time) ? c.strftime(CSV_DATE_FORMAT) : c }
        )
      end
    end
  end

  def serialize_model!(name, model, opts)
    model[name].merge!(
      ScenarioSerializer.new(self).serializable_hash(:include => [])
        .except(*[:links]).deep_stringify_keys
    )
  end

  class InvalidState < StandardError
  end

  private
    def campaign_check
      campaign_was = Campaign
        .find_by_id(campaign_id_was) if !campaign_id_was.nil?

      if campaign_id_changed? && !campaign_was.nil? &&
        campaign_was.state != Campaign::CREATED
        errors.add(:campaign_id,
          'unable to modify after campaign starts')
      end

      if campaign_id_changed? && !campaign.nil? &&
        campaign.state == Campaign::FINISHED
        errors.add(:campaign_id,
          'unable to add to a finished campaign')
      end

      if !campaign_id_changed? && changed? && !campaign.nil? &&
        campaign.state == Campaign::FINISHED
        changes.each do |k, v|
          attribute = k.to_sym
          errors.add(attribute,
            'unable to modify after campaign finishes')
        end
      end
    end

    def victims_summary
      Victim.joins(:report).includes(:report).where(:scenario_id => id)
        .find_each(:batch_size => batch_size).lazy.map do |v|
        v.summary.concat(
          v.report.goals.sort_by{ |g| [-g['score'], g['goal_id']] }.map { |g|
            [g[COL_HIT],
             g[COL_REPORTED_DATE] ? Time.iso8601(g[COL_REPORTED_DATE]) : nil,
             g.dig(COL_DATA, COL_IP),
             g.dig(COL_DATA, COL_USER_AGENT),
             g.dig(COL_DATA, COL_COOKIE),
             g[COL_DATA] ? g[COL_DATA].to_json : '']
          }.flatten
        )
      end
    end

    def batch_size
      @batch_size ||= Rails.configuration.pompa.batch_size
    end
end
