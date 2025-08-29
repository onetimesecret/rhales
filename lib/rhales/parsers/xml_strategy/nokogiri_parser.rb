# lib/rhales/parsers/xml_strategy/nokogiri_parser.rb

require 'nokogiri'
require_relative 'base_parser'

module Rhales
  module Parsers
    module XmlStrategy
      # Strategy to parse .rue files using the Nokogiri parser.
      class NokogiriParser < BaseParser
        def parse(xml_content)
          # Wrap content in a root to handle multiple top-level sections
          doc = Nokogiri::XML("<root>#{xml_content}</root>") do |config|
            config.strict.noblanks.noent.nonet
          end

          doc.root.children.map do |node|
            next unless node.element?
            {
              tag: node.name,
              attributes: node.attributes.transform_values(&:value),
              content: node.inner_html.strip
            }
          end.compact
        rescue Nokogiri::XML::SyntaxError => e
          raise Rhales::ParseError, "Invalid .rue file structure: #{e.message}"
        end
      end
    end
  end
end
