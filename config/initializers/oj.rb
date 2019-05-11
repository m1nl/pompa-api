require 'active_support/core_ext'
require 'active_support/json'
require 'oj'

Oj.mimic_JSON
Oj.add_to_json
Oj.optimize_rails
