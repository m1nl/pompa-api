class Goal < ApplicationRecord
  include Defaults
  include Pageable
  include Model

  belongs_to :template, required: true
  has_many :goal

  validates :name, :code, presence: true
  validates :score, numericality: { only_integer: true }

  default :code, proc { Pompa::Utils.random_code }

  build_model_prepend :template

  after_commit :clear_cached_values

  def serialize_model!(name, model, opts)
    model[name].merge!(
      GoalSerializer.new(self).serializable_hash(:include => [])
        .except(*[:links]).deep_stringify_keys
    )
  end

  def dup
    super.tap { |c| c.code = Pompa::Utils.random_code }
  end

  def clear_cached_values
    self.class.clear_cached_values(code)
  end

  class << self
    def id_by_code(goal_code)
      Pompa::Cache.fetch("goal_#{goal_code}/id") do
        Goal.where(code: goal_code).pick(:id)
      end
    end

    def template_id_by_code(goal_code)
      Pompa::Cache.fetch("goal_#{goal_code}/template_id") do
        Goal.where(code: goal_code).pick(:template_id)
      end
    end

    def clear_cached_values(goal_code)
      Pompa::Cache.delete("goal_#{goal_code}/id")
      Pompa::Cache.delete("goal_#{goal_code}/template_id")
    end
  end
end
