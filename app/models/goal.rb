class Goal < ApplicationRecord
  include Defaults
  include Pageable
  include Model

  belongs_to :template, required: true
  has_many :goal

  validates :name, :score, :code, presence: true

  default :code, proc { Pompa::Utils.random_code }

  build_model_prepend :template

  def serialize_model!(name, model, opts)
    model[name].merge!(
      GoalSerializer.new(self).serializable_hash(:include => [])
        .except(*[:links]).deep_stringify_keys
    )
  end

  class << self
    def id_by_code(goal_code)
      Pompa::Cache.fetch("goal_#{goal_code}/id") do
        Goal.where(code: goal_code).pluck(:id).first
      end
    end

    def template_id_by_code(goal_code)
      Pompa::Cache.fetch("goal_#{goal_code}/template_id") do
        Goal.where(code: goal_code).pluck(:template_id).first
      end
    end
  end
end
