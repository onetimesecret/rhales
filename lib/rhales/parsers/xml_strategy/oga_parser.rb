# lib/rhales/parsers/xml_strategy/oga_parser.rb

require_relative 'base_parser'

module Rhales
  module Parsers
    module XmlStrategy
      # Strategy to parse .rue files using the Oga parser.
      class OgaParser < BaseParser
        def parse(xml_content)
          doc = Oga.parse_xml(xml_content)
          doc.children.map do |node|
            next unless node.is_a?(Oga::XML::Element)
            {
              tag: node.name,
              attributes: node.attributes.each_with_object({}) { |attr, h| h[attr.name] = attr.value },
              content: node.inner_text
            }
          end.compact
        rescue LL::ParserError => e
          raise Rhales::ParseError, "Invalid .rue file structure: #{e.message}"
        end
      end
    end
  end
end
