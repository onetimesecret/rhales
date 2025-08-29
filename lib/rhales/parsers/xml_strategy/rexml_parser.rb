# lib/rhales/parsers/xml_strategy/rexml_parser.rb

require 'rexml/document'
require_relative 'base_parser'

module Rhales
  module Parsers
    module XmlStrategy
      # Strategy to parse .rue files using the standard library's REXML.
      class RexmlParser < BaseParser
        def parse(xml_content)
          doc = REXML::Document.new("<root>#{xml_content}</root>")
          doc.root.elements.map do |node|
            {
              tag: node.name,
              attributes: node.attributes,
              # REXML children include text nodes, so join them.
              # This is a simplified way to get inner HTML.
              content: node.children.map(&:to_s).join.strip
            }
          end
        rescue REXML::ParseException => e
          # Wrap REXML error in a standard error type
          raise Rhales::ParseError, "Invalid .rue file structure: #{e.message}"
        end
      end
    end
  end
end
