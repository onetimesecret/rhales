# lib/rhales/parsers/xml_strategy_factory.rb

module Rhales
  module Parsers
    # Factory for selecting and creating an XML parser strategy.
    module XmlStrategyFactory
      def self.create(parser_name = nil)
        parser_name ||= Rhales.config.xml_parser || detect_best_available

        case parser_name.to_sym
        when :nokogiri
          require_and_instantiate('nokogiri', 'XmlStrategy::NokogiriParser')
        when :oga
          require_and_instantiate('oga', 'XmlStrategy::OgaParser')
        when :rexml
          instantiate('XmlStrategy::RexmlParser')
        else
          raise Rhales::ConfigurationError, "Unknown XML parser: #{parser_name}. Available: :nokogiri, :oga, :rexml"
        end
      end

      private

      def self.detect_best_available
        if try_require('nokogiri')
          :nokogiri
        elsif try_require('oga')
          :oga
        else
          :rexml
        end
      end

      def self.try_require(lib)
        require lib
        true
      rescue LoadError
        false
      end

      def self.require_and_instantiate(lib, class_name)
        require lib
        instantiate(class_name)
      rescue LoadError
        raise Rhales::ConfigurationError, "XML parser '#{lib}' is configured but the gem is not installed. Please add it to your Gemfile."
      end

      def self.instantiate(class_name)
        Rhales::Parsers.const_get(class_name).new
      end
    end
  end
end
