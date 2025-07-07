# lib/rhales/refinements/require_refinements.rb

require_relative '../rue_document'

module Rhales
  module Ruequire
    # Thread-safe cache for parsed RSFC templates
    @rsfc_cache     = {}
    @file_watchers  = {}
    @cache_mutex    = Mutex.new
    @watchers_mutex = Mutex.new

    class << self
      # Thread-safe access to cache
      def rsfc_cache
        @cache_mutex.synchronize { @rsfc_cache.dup }
      end

      # Thread-safe access to file watchers
      def file_watchers
        @watchers_mutex.synchronize { @file_watchers.dup }
      end

      # Clear cache (useful for development and testing)
      def clear_cache!
        @cache_mutex.synchronize { @rsfc_cache.clear }
        cleanup_file_watchers!
      end

      # Stop all file watchers and clean up resources
      def cleanup_file_watchers!
        @watchers_mutex.synchronize do
          @file_watchers.each_value do |watcher_thread|
            next unless watcher_thread.is_a?(Thread) && watcher_thread.alive?

            watcher_thread.kill
            begin
              watcher_thread.join(1) # Wait up to 1 second for clean shutdown
            rescue StandardError
              # Thread might already be dead, ignore errors
            end
          end
          @file_watchers.clear
        end
      end

      # Stop watching a specific file
      def stop_watching_file!(full_path)
        @watchers_mutex.synchronize do
          watcher_thread = @file_watchers.delete(full_path)
          if watcher_thread.is_a?(Thread) && watcher_thread.alive?
            watcher_thread.kill
            begin
              watcher_thread.join(1)
            rescue StandardError
              # Thread cleanup error, ignore
            end
          end
        end
      end

      # Enable development mode file watching
      def enable_file_watching!
        @file_watching_enabled = true
      end

      # Disable file watching
      def disable_file_watching!
        @file_watching_enabled = false
      end

      def file_watching_enabled?
        @file_watching_enabled ||= false
      end
    end

    # Ensure cleanup on program exit
    at_exit do
      if defined?(Rhales::Ruequire)
        Rhales::Ruequire.cleanup_file_watchers!
      end
    end

    refine Kernel do
      def require(path)
        return process_rue(path) if path.end_with?('.rue')

        super
      end

      def process_rue(path)
        # Resolve full path
        full_path = resolve_rue_path(path)

        unless File.exist?(full_path)
          raise LoadError, "cannot load such file -- #{path} (resolved to #{full_path})"
        end

        # Check cache first
        cached_parser = get_cached_parser(full_path)
        return cached_parser if cached_parser

        # Parse the .rue file
        parser = Rhales::RueDocument.parse_file(full_path)

        # Cache the parsed result
        cache_parser(full_path, parser)

        # Set up file watching in development mode
        setup_file_watching(full_path) if Rhales::Ruequire.file_watching_enabled?

        parser
      rescue StandardError => ex
        if defined?(OT) && OT.respond_to?(:le)
          OT.le "[RSFC] Failed to process .rue file #{path}: #{ex.message}"
        else
          puts "[RSFC] Failed to process .rue file #{path}: #{ex.message}"
        end
        raise
      end

      private

      # Resolve .rue file path
      def resolve_rue_path(path)
        # If path is absolute and exists, use it
        return path if path.start_with?('/') && File.exist?(path)

        # If path is relative and exists in current directory
        return File.expand_path(path) if File.exist?(path)

        # Search in templates directory
        boot_root      = defined?(OT) && OT.respond_to?(:boot_root) ? OT.boot_root : File.expand_path('../../..', __dir__)
        templates_path = File.join(boot_root, 'templates', path)
        return templates_path if File.exist?(templates_path)

        # Search in templates/web directory
        web_templates_path = File.join(boot_root, 'templates', 'web', path)
        return web_templates_path if File.exist?(web_templates_path)

        # If path doesn't have .rue extension, add it and try again
        unless path.end_with?('.rue')
          return resolve_rue_path("#{path}.rue")
        end

        # Return original path (will cause file not found error)
        path
      end

      # Get parser from cache if available and not stale
      def get_cached_parser(full_path)
        Rhales::Ruequire.instance_variable_get(:@cache_mutex).synchronize do
          cache_entry = Rhales::Ruequire.instance_variable_get(:@rsfc_cache)[full_path]
          return nil unless cache_entry

          # Check if file has been modified
          if File.mtime(full_path) > cache_entry[:mtime]
            # File modified, remove from cache
            Rhales::Ruequire.instance_variable_get(:@rsfc_cache).delete(full_path)
            return nil
          end

          cache_entry[:parser]
        end
      end

      # Cache parsed parser with modification time
      def cache_parser(full_path, parser)
        Rhales::Ruequire.instance_variable_get(:@cache_mutex).synchronize do
          Rhales::Ruequire.instance_variable_get(:@rsfc_cache)[full_path] = {
            parser: parser,
            mtime: File.mtime(full_path),
          }
        end
      end

      # Set up file watching for development mode
      def setup_file_watching(full_path)
        # Check if already watching in a thread-safe way
        watchers_mutex      = Rhales::Ruequire.instance_variable_get(:@watchers_mutex)
        is_already_watching = watchers_mutex.synchronize do
          Rhales::Ruequire.instance_variable_get(:@file_watchers)[full_path]
        end

        return if is_already_watching

        # Simple polling-based file watching
        # In a production system, you might want to use a more sophisticated
        # file watching library like Listen or rb-inotify
        watcher_thread = Thread.new do
          last_mtime = File.mtime(full_path)

          loop do
            sleep 1 # Check every second

            begin
              current_mtime = File.mtime(full_path)

              if current_mtime > last_mtime
                if defined?(OT) && OT.respond_to?(:ld)
                  OT.ld "[RSFC] File changed, clearing cache: #{full_path}"
                end

                # Thread-safe cache removal
                Rhales::Ruequire.instance_variable_get(:@cache_mutex).synchronize do
                  Rhales::Ruequire.instance_variable_get(:@rsfc_cache).delete(full_path)
                end

                last_mtime = current_mtime
              end
            rescue StandardError => ex
              # File might have been deleted
              if defined?(OT) && OT.respond_to?(:ld)
                OT.ld "[RSFC] File watcher error for #{full_path}: #{ex.message}"
              end

              # Clean up watcher entry on error
              watchers_mutex.synchronize do
                Rhales::Ruequire.instance_variable_get(:@file_watchers).delete(full_path)
              end
              break
            end
          end
        end

        # Set thread as daemon so it doesn't prevent program exit
        watcher_thread.thread_variable_set(:daemon, true)

        # Mark as being watched
        watchers_mutex.synchronize do
          Rhales::Ruequire.instance_variable_get(:@file_watchers)[full_path] = watcher_thread
        end
      end
    end
  end
end
