require 'csv'

class Target < ApplicationRecord
  include Pageable
  include NullifyBlanks

  FEMALE = 'female'.freeze
  MALE = 'male'.freeze

  CSV_ROW = [:first_name, :last_name, :email, :gender, :department, :comment, :group_id].freeze

  belongs_to :group, required: true
  has_one :victim, required: false
  has_one :quicksearch, foreign_key: 'target_id',
    class_name: 'TargetQuicksearch'

  validates :first_name, :last_name, :email, presence: true
  validates :email, format: { with: /@/, message: "provide a valid email" }
  validates :gender, inclusion: { in: [FEMALE, MALE, nil] }

  nullify_blanks :gender, :department, :comment

  scope :quicksearch, ->(term) { joins(:quicksearch)
    .merge(TargetQuicksearch.search(term)) }

  def display_name
    "#{first_name} #{last_name}"
  end

  class << self
    def upload_csv(file, params)
      ids = []

      ActiveRecord::Base.transaction do
        targets = []

        CSV.foreach(file.path) do |r|
          target = Hash[CSV_ROW.zip(r)].merge(params)
          targets << Target.new(target)

          if targets.length >= batch_size
            ids.concat Target.import(targets, validate => true)[:ids]
            targets = []
          end
        end

        if targets.length != 0
          ids.concat Target.import(targets, validate => true)[:ids]
        end
      end

      return ids
    end

    def batch_size
      @batch_size ||= Rails.configuration.pompa.batch_size
    end
  end
end
