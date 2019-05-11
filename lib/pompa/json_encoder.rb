# based on standard ActiveSupport JSONGemEncoder, includes escaping of Unicode control characters
require 'oj'

module Pompa
  class JsonEncoder
    attr_reader :options

    def initialize(options = nil)
      @options = options || {}
    end

    # Encode the given object into a JSON string
    def encode(value)
      stringify jsonify value.as_json(options.dup)
    end

    private
      # Rails does more escaping than the JSON gem natively does (we
      # escape \u2028 and \u2029 and optionally >, <, & to work around
      # certain browser problems).
      ESCAPED_CHARS = {
        "\u2028" => '\u2028',
        "\u2029" => '\u2029',
        # BEGIN Unicode control characters
        "\u061c" => '\u061c',
        "\u200e" => '\u200e',
        "\u200f" => '\u200f',
        "\u202a" => '\u202a',
        "\u202b" => '\u202b',
        "\u202c" => '\u202c',
        "\u202d" => '\u202d',
        "\u202e" => '\u202e',
        # END
        ">"      => '\u003e',
        "<"      => '\u003c',
        "&"      => '\u0026',
        }

      ESCAPE_REGEX_WITH_HTML_ENTITIES = /[\u2028\u2029\u061c\u200e\u200f\u202a\u202b\u202c\u202d\u202e><&]/u
      ESCAPE_REGEX_WITHOUT_HTML_ENTITIES = /[\u2028\u2029\u061c\u200e\u200f\u202a\u202b\u202c\u202d\u202e]/u

      # This class wraps all the strings we see and does the extra escaping
      class EscapedString < String #:nodoc:
        def to_json(*)
          if ActiveSupport::JSON::Encoding.escape_html_entities_in_json
            super.gsub ESCAPE_REGEX_WITH_HTML_ENTITIES, ESCAPED_CHARS
          else
            super.gsub ESCAPE_REGEX_WITHOUT_HTML_ENTITIES, ESCAPED_CHARS
          end
        end

        def to_s
          self
        end
      end

      # Mark these as private so we don't leak encoding-specific constructs
      private_constant :ESCAPED_CHARS, :ESCAPE_REGEX_WITH_HTML_ENTITIES,
        :ESCAPE_REGEX_WITHOUT_HTML_ENTITIES, :EscapedString

      # Convert an object into a "JSON-ready" representation composed of
      # primitives like Hash, Array, String, Numeric,
      # and +true+/+false+/+nil+.
      # Recursively calls #as_json to the object to recursively build a
      # fully JSON-ready object.
      #
      # This allows developers to implement #as_json without having to
      # worry about what base types of objects they are allowed to return
      # or having to remember to call #as_json recursively.
      #
      # Note: the +options+ hash passed to +object.to_json+ is only passed
      # to +object.as_json+, not any of this method's recursive +#as_json+
      # calls.
      def jsonify(value)
        case value
        when String
          EscapedString.new(value)
        when Numeric, NilClass, TrueClass, FalseClass
          value.as_json
        when Hash
          Hash[value.map { |k, v| [jsonify(k), jsonify(v)] }]
        when Array
          value.map { |v| jsonify(v) }
        else
          jsonify value.as_json
        end
      end

      # Encode a "jsonified" Ruby data structure using the JSON gem
      def stringify(jsonified)
        Oj.dump(jsonified, quirks_mode: true, max_nesting: false)
      end
  end
end
