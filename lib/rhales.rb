# lib/rhales.rb

require_relative 'rhales/version'
require_relative 'rhales/errors'
require_relative 'rhales/configuration'
require_relative 'rhales/adapters/base_auth'
require_relative 'rhales/adapters/base_session'
require_relative 'rhales/context'
require_relative 'rhales/rue_document'
require_relative 'rhales/parsers/handlebars_parser'
require_relative 'rhales/parsers/rue_format_parser'
require_relative 'rhales/parsers/xml_strategy_factory'
require_relative 'rhales/parsers/xml_strategy/base_parser'
require_relative 'rhales/parsers/xml_strategy/rexml_parser'
require_relative 'rhales/parsers/xml_strategy/oga_parser'
require_relative 'rhales/parsers/xml_strategy/nokogiri_parser'
require_relative 'rhales/template_engine'
require_relative 'rhales/hydrator'
require_relative 'rhales/view_composition'
require_relative 'rhales/hydration_data_aggregator'
require_relative 'rhales/mount_point_detector'
require_relative 'rhales/safe_injection_validator'
require_relative 'rhales/earliest_injection_detector'
require_relative 'rhales/link_based_injection_detector'
require_relative 'rhales/hydration_injector'
require_relative 'rhales/hydration_endpoint'
require_relative 'rhales/refinements/require_refinements'
require_relative 'rhales/view'

# Ruby Single File Components (RSFC)
#
# A framework for building server-rendered components with client-side hydration
# using .rue files (Ruby Single File Components). Similar to .vue files but for Ruby.
#
# Features:
# - Server-side template rendering with Handlebars-style syntax
# - Client-side data hydration with JSON injection
# - Partial support for component composition
# - Pluggable authentication and session adapters
# - Security-first design with XSS protection and CSP support
#
# Usage:
#   Rhales.configure do |config|
#     config.default_locale = 'en'
#     config.template_paths = ['app/templates']
#     config.features = { dark_mode: true }
#
#     # Hydration configuration
#     config.hydration.injection_strategy = :early  # :early or :late (default)
#     config.hydration.mount_point_selectors = ['#app', '#root', '[data-mount]']
#     config.hydration.fallback_to_late = true
#   end
#
#   view = Rhales::View.new(request, session, user)
#   html = view.render('my_component')
module Rhales
  # Convenience method to create a view with props
  def self.render(template_name, request: nil, session: nil, user: nil, locale: nil, **props)
    view = View.new(request, session, user, locale, props: props)
    view.render(template_name)
  end

  # Quick template rendering for testing/simple use cases
  def self.render_template(template_content, context_data = {})
    context = Context.minimal(props: context_data)
    TemplateEngine.render(template_content, context)
  end

  # Create context with props (for advanced usage)
  def self.create_context(request: nil, session: nil, user: nil, locale: nil, **props)
    Context.for_view(request, session, user, locale, **props)
  end
end
