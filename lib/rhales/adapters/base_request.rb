# lib/rhales/adapters/base_request.rb
#
# frozen_string_literal: true

module Rhales
  module Adapters
    # Base request adapter interface
    #
    # Defines the contract that request adapters must implement
    # to work with Rhales. This allows the library to work with any
    # web framework by implementing this interface.
    class BaseRequest
      # Get request path
      def path
        raise NotImplementedError, 'Subclasses must implement #path'
      end

      # Get request method
      def method
        raise NotImplementedError, 'Subclasses must implement #method'
      end

      # Get client IP
      def ip
        raise NotImplementedError, 'Subclasses must implement #ip'
      end

      # Get request parameters
      def params
        raise NotImplementedError, 'Subclasses must implement #params'
      end

      # Get request environment
      def env
        raise NotImplementedError, 'Subclasses must implement #env'
      end
    end

    # Simple request adapter for framework integration
    class SimpleRequest < BaseRequest
      attr_reader :request_path, :request_method, :client_ip, :request_params, :request_env

      def initialize(path: '/', method: 'GET', ip: '127.0.0.1', params: {}, env: {})
        @request_path = path
        @request_method = method
        @client_ip = ip
        @request_params = params
        @request_env = env
      end

      def path
        @request_path
      end

      def method
        @request_method
      end

      def ip
        @client_ip
      end

      def params
        @request_params
      end

      def env
        @request_env
      end
    end

    # Framework request adapter wrapper
    class FrameworkRequest < BaseRequest
      def initialize(framework_request)
        @framework_request = framework_request
      end

      def path
        @framework_request.path
      end

      def method
        @framework_request.request_method
      end

      def ip
        @framework_request.ip
      end

      def params
        @framework_request.params
      end

      def env
        @framework_request.env
      end
    end
  end
end
