class Group < ApplicationRecord
  include Pageable
  include Model

  has_many :targets

  validates :name, presence: true

  def clear
    Target.where(group_id: id).delete_all
  end

  def serialize_model!(name, model, opts)
    model[name].merge!(
      GroupSerializer.new(self).serializable_hash(:include => [])
        .except(*[:links]).deep_stringify_keys
   )
  end
end
