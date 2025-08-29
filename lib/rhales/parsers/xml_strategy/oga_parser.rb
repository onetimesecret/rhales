# lib/rhales/parsers/xml_strategy/oga_parser.rb

require 'oga'
require_relative 'base_parser'

module Rhales
  module Parsers
    module XmlStrategy
      # Strategy to parse .rue files using the Oga parser.
      class OgaParser < BaseParser
        def parse(xml_content)
          # Oga is more lenient and may not raise an error on malformed XML.
          # We add a basic check for mismatched tags to enforce structure.
          validate_structure!(xml_content)

          # Wrap content in a root to handle multiple top-level sections like other parsers
          doc = Oga.parse_xml("<root>#{xml_content}</root>")
          root_element = doc.children.find { |n| n.is_a?(Oga::XML::Element) && n.name == 'root' }
          elements = root_element ? root_element.children : []

          elements.map do |node|
            next unless node.is_a?(Oga::XML::Element)

            {
              tag: node.name,
              attributes: node.attributes.each_with_object({}) { |attr, h| h[attr.name] = attr.value },
              content: node.children.map(&:to_xml).join.strip
            }
          end.compact
        rescue LL::ParserError => e
          raise Rhales::ParseError, "Invalid .rue file structure: #{e.message}"
        end

        private

        # Basic validation to check for mismatched tags, since Oga can be too lenient.
        def validate_structure!(xml_content)
          # We expect sections to be siblings, not nested.
          # A simple regex check can help catch basic malformations.
          if xml_content.scan(/<data/).count != xml_content.scan(%r{</data>}).count ||
             xml_content.scan(/<template/).count != xml_content.scan(%r{</template>}).count ||
             xml_content.scan(/<logic/).count != xml_content.scan(%r{</logic>}).count
            raise Rhales::ParseError, 'Malformed .rue file: unclosed or mismatched tags detected.'
          end
        end
      end
    end
  end
end
