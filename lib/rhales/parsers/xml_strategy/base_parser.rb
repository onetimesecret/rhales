# lib/rhales/parsers/xml_strategy/base_parser.rb

module Rhales
  module Parsers
    module XmlStrategy
      # Defines the interface for all XML parsing strategies.
      class BaseParser
        # Parses an XML string and returns a standardized array of hashes.
        #
        # @param xml_content [String] The XML content of the .rue file.
        # @return [Array<Hash>] An array where each hash represents a section.
        #   e.g., [{ tag: 'data', attributes: { 'window' => 'app' }, content: '...' }]
        def parse(xml_content)
          raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
        end
      end
    end
  end
end
