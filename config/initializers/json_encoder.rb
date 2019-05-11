require 'pompa/json_encoder'

ActiveSupport::JSON::Encoding.json_encoder = Pompa::JsonEncoder
