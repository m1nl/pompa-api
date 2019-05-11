class WorkerResponse
  include ActiveModel::Model
  include ActiveModel::Serialization

  attr_accessor :id, :status, :value, :broadcast, :result, :worker_id

  def initialize(attributes = {})
    @id = attributes[:id]
    @status = attributes[:status]
    @value = attributes[:value]
    @broadcast = attributes[:broadcast]
    @result = attributes[:result]
    @worker_id = attributes[:worker_id]
  end

  def worker
    Worker.find_by_id(worker_id) unless worker_id.nil?
  end

  class << self
    def wrap(response)
      self.new(
        :id => response.dig(:request_id),
        :status => response.dig(:result, :status),
        :value => response.dig(:result, :value),
        :broadcast => response.dig(:broadcast) || false,
        :result => (response.dig(:result) || {}).except(:status, :value),
        :worker_id => response.dig(:origin, :id),
      )
    end
  end
end
