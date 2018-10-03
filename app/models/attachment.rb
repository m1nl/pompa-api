require 'liquid'

class Attachment < ApplicationRecord
  include Pageable
  include LiquidTemplate
  include Model

  FILENAME = 'filename'.freeze

  belongs_to :template, required: true
  belongs_to :resource, required: true

  validates :name, :filename, presence: true

  build_model_prepend :resource

  liquid_template :filename

  def serialize_model!(name, model, opts)
    model[name].merge!(
      AttachmentSerializer.new(self)
        .serializable_hash(:include => []).except!(*[:filename, :links])
        .deep_stringify_keys
    )
    model[name].merge!(
      { FILENAME => Pompa::Utils.sanitize_filename(
          filename_template.render!(model, Pompa::Utils.liquid_flags)) }
    )
  end
end
