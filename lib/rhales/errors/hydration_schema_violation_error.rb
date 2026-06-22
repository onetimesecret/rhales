# lib/rhales/errors/hydration_schema_violation_error.rb
#
# frozen_string_literal: true

module Rhales
  # Raised when `schema_projection` is `:strict` and the client data passed to a
  # view contains top-level keys that are not declared in the template's
  # `<schema>`.
  #
  # In `:strict` mode the schema is treated as an exhaustive allowlist for client
  # data: any undeclared key is a programming error (most often sensitive server
  # data that was never meant to cross to the browser), so it fails loudly
  # instead of being silently emitted (`:off`) or silently dropped (`:strip`).
  class HydrationSchemaViolationError < Error
    attr_reader :template, :undeclared_keys

    def initialize(template, undeclared_keys)
      @template        = template
      @undeclared_keys = Array(undeclared_keys)

      super(build_message)
    end

    private

    def build_message
      <<~MSG.strip
        Hydration schema violation

        Template: #{@template}
        Undeclared client keys: #{@undeclared_keys.join(', ')}

        schema_projection is :strict, so the <schema> is treated as an exhaustive
        allowlist for client data. Each key listed above was passed to the view
        but is not declared in the schema.

        Quick fixes:
          1. Declare the keys in the template <schema> if they are safe to expose.
          2. Remove the keys from the data passed to the view (client:).
          3. Set schema_projection = :strip to drop undeclared keys instead of raising.

        Learn more: https://rhales.dev/docs/data-boundaries
      MSG
    end
  end
end
