# lib/rhales/errors.rb
# frozen_string_literal: true

module Rhales
  class Error < StandardError; end

  # Parse-time errors - syntax and structure issues
  class ParseError < Error
    attr_reader :line, :column, :offset, :source_type

    def initialize(message, line: nil, column: nil, offset: nil, source_type: nil)
      @line        = line
      @column      = column
      @offset      = offset
      @source_type = source_type  # :rue, :handlebars, or :template

      location = line && column ? " at line #{line}, column #{column}" : ''
      source   = source_type ? " in #{source_type}" : ''
      super("#{message}#{location}#{source}")
    end
  end

  # Validation-time errors - structural and semantic issues
  class ValidationError < Error; end

  # Render-time errors - runtime issues during template execution
  class RenderError < Error; end

  # Configuration errors
  class ConfigurationError < Error; end

  # Legacy alias for backward compatibility
  class TemplateError < Error; end
end

# Load specific error classes
require_relative 'errors/hydration_collision_error'
