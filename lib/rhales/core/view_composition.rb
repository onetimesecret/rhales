# lib/rhales/view_composition.rb

require_relative 'rue_document'
require_relative '../integrations/refinements/require_refinements'

using Rhales::Ruequire

module Rhales
  # ViewComposition builds and represents the complete template dependency graph
  # for a view render. It provides a data-agnostic, immutable representation
  # of all templates (layout, view, partials) required for rendering.
  #
  # This class is a key component in the two-pass rendering architecture,
  # enabling server-side data aggregation before HTML generation.
  #
  # Responsibilities:
  # - Dependency Resolution: Recursively discovers and loads all partials
  # - Structural Representation: Organizes templates into a traversable tree
  # - Traversal Interface: Provides methods to iterate templates in render order
  #
  # Key Characteristics:
  # - Data-Agnostic: Knows nothing about runtime context or request data
  # - Immutable: Once created, the composition is read-only
  # - Cacheable: Can be cached in production for performance
  class ViewComposition
    include Rhales::Utils::LoggingHelpers

    class TemplateNotFoundError < StandardError; end
    class CircularDependencyError < StandardError; end

    attr_reader :root_template_name, :templates, :dependencies

    def initialize(root_template_name, loader:, config: nil)
      @root_template_name = root_template_name
      @loader             = loader
      @config             = config
      @templates          = {}
      @dependencies       = {}
      @loading            = Set.new
    end

    # Resolve all template dependencies
    def resolve!
      log_timed_operation(Rhales.logger, :debug, 'Template dependency resolution',
        root_template: @root_template_name
      ) do
        load_template_recursive(@root_template_name)
        freeze_composition

        # Log resolution results
        log_with_metadata(Rhales.logger, :info, 'Template composition resolved',
          root_template: @root_template_name,
          total_templates: @templates.size,
          total_dependencies: @dependencies.values.sum(&:size),
          partials: @dependencies.values.flatten.uniq,
          layout: layout
        )

        self
      end
    end

    # Iterate through all documents in render order
    # Layout -> View -> Partials (depth-first)
    def each_document_in_render_order(&)
      return enum_for(:each_document_in_render_order) unless block_given?

      visited = Set.new

      # Process layout first if specified
      root_doc = @templates[@root_template_name]
      if root_doc && root_doc.layout
        layout_name = root_doc.layout
        if @templates[layout_name]
          yield_template_recursive(layout_name, visited, &)
        end
      end

      # Then process the root template and its dependencies
      yield_template_recursive(@root_template_name, visited, &)
    end

    # Get a specific template by name
    def template(name)
      @templates[name]
    end

    # Check if a template exists in the composition
    def template?(name)
      @templates.key?(name)
    end

    # Get all template names
    def template_names
      @templates.keys
    end

    # Get direct dependencies of a template
    def dependencies_of(template_name)
      @dependencies[template_name] || []
    end

    # Get the layout for the root template (if any)
    def layout
      root_template = @templates[@root_template_name]
      return nil unless root_template

      root_template.layout
    end

    private

    def load_template_recursive(template_name, parent_path = nil)
      depth = @loading.size

      # Check for circular dependencies
      if @loading.include?(template_name)
        log_with_metadata(Rhales.logger, :error, 'Circular dependency detected',
          template: template_name,
          dependency_chain: @loading.to_a,
          depth: depth
        )
        raise CircularDependencyError, "Circular dependency detected: #{template_name} -> #{@loading.to_a.join(' -> ')}"
      end

      # Skip if already loaded (cache hit)
      if @templates.key?(template_name)
        Rhales.logger.debug("Template cache hit: template=#{template_name}")
        return
      end

      @loading.add(template_name)

      begin
        # Load template using the provided loader
        start_time = now_in_μs
        parser = @loader.call(template_name)
        load_duration = now_in_μs - start_time

        unless parser
          log_with_metadata(Rhales.logger, :error, 'Template not found',
            template: template_name,
            parent: parent_path,
            depth: depth,
            search_duration: load_duration
          )
          raise TemplateNotFoundError, "Template not found: #{template_name}"
        end

        # Store the template
        @templates[template_name]    = parser
        @dependencies[template_name] = []

        # Extract and load partials
        partials = extract_partials(parser)

        if partials.any?
          log_with_metadata(Rhales.logger, :debug, 'Partial resolution',
            template: template_name,
            partials_found: partials,
            partial_count: partials.size,
            depth: depth,
            load_duration: load_duration
          )
        end

        partials.each do |partial_name|
          @dependencies[template_name] << partial_name
          load_template_recursive(partial_name, template_name)
        end

        # Load layout if specified and not already loaded
        if parser.layout && !@templates.key?(parser.layout)
          log_with_metadata(Rhales.logger, :debug, 'Layout resolution',
            template: template_name,
            layout: parser.layout,
            depth: depth
          )
          load_template_recursive(parser.layout, template_name)
        end

        # Log successful template load
        log_with_metadata(Rhales.logger, :debug, 'Template loaded',
          template: template_name,
          parent: parent_path,
          depth: depth,
          has_partials: partials.any?,
          has_layout: !parser.layout.nil?,
          load_duration: load_duration
        )
      ensure
        @loading.delete(template_name)
      end
    end

    def extract_partials(parser)
      partials         = Set.new
      template_content = parser.section('template')

      return partials unless template_content

      # Extract partial references from template
      # Looking for {{> partial_name}} patterns
      template_content.scan(/\{\{>\s*([^\s}]+)\s*\}\}/) do |match|
        partials.add(match[0])
      end

      partials
    end

    def yield_template_recursive(template_name, visited, &)
      return if visited.include?(template_name)

      visited.add(template_name)

      # First yield dependencies (partials)
      (@dependencies[template_name] || []).each do |dep_name|
        yield_template_recursive(dep_name, visited, &)
      end

      # Then yield the template itself
      if @templates[template_name]
        yield template_name, @templates[template_name]
      end
    end

    def freeze_composition
      @templates.freeze
      @dependencies.freeze
      @templates.each_value(&:freeze)
      @dependencies.each_value(&:freeze)
      freeze
    end
  end
end
