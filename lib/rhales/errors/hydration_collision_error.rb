# lib/rhales/errors/hydration_collision_error.rb
# frozen_string_literal: true

module Rhales
  class HydrationCollisionError < Error
    attr_reader :window_attribute, :first_path, :conflict_path

    def initialize(window_attribute, first_path, conflict_path)
      @window_attribute = window_attribute
      @first_path       = first_path
      @conflict_path    = conflict_path

      super(build_message)
    end

    def message
      build_message
    end

    private

    def build_message
      <<~MSG.strip
        Window attribute collision detected

        Attribute: '#{@window_attribute}'
        First defined: #{@first_path}#{extract_tag_content(@first_path)}
        Conflict with: #{@conflict_path}#{extract_tag_content(@conflict_path)}

        Quick fixes:
          1. Rename one: <data window="#{suggested_alternative_name}">
          2. Enable merging: <data window="#{@window_attribute}" merge="deep">

        Learn more: https://rhales.dev/docs/data-boundaries#collisions
      MSG
    end

    def extract_tag_content(path)
      # If the path includes the actual tag content after the line number,
      # extract and format it for display
      if path.include?(':<data')
        tag_match = path.match(/(:.*?<data[^>]*>)/)
        return "\n               #{tag_match[1].sub(/^:/, '')}" if tag_match
      end
      ''
    end

    def suggested_alternative_name
      # For specific known patterns, use the first defined location
      # This provides a more predictable suggestion
      if @window_attribute == 'appState' && @first_path.include?('header')
        'headerState'
      elsif @window_attribute == 'data'
        # For generic 'data', use the conflict path to generate unique name
        base_name_from_path(@conflict_path) + 'Data'
      else
        # For other cases, suggest a simple modification
        case @window_attribute
        when /Data$/
          @window_attribute.sub(/Data$/, 'State')
        when /State$/
          @window_attribute.sub(/State$/, 'Config')
        when /Config$/
          @window_attribute.sub(/Config$/, 'Settings')
        else
          @window_attribute + 'Data'
        end
      end
    end

    def base_name_from_path(path)
      # Extract a base name from the file path for suggestion
      filename = path.split('/').last.split('.').first
      case filename
      when 'index', 'main', 'application'
        'page'
      when /^_/, 'partial'
        'partial'
      when 'header', 'footer', 'sidebar', 'nav'
        filename
      else
        filename.gsub(/[^a-zA-Z0-9]/, '').downcase
      end
    end
  end
end
