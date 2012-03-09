module Stooge
  class Worker

    def self.run!
      Stooge.log "Starting stooge"

      Signal.trap('INT') { AMQP.stop{ EM.stop } }
      Signal.trap('TERM'){ AMQP.stop{ EM.stop } }

      Stooge.start
    end

    def self.run?
      Stooge.handlers? &&
        File.expand_path($0) == File.expand_path(app_file)
    end

    private

      CALLERS_TO_IGNORE = [
        /\/stooge(\/worker)?\.rb$/,
        /rubygems\/custom_require\.rb$/,
        /bundler(\/runtime)?\.rb/,
        /<internal:/
      ]

      CALLERS_TO_IGNORE.concat(RUBY_IGNORE_CALLERS) if defined?(RUBY_IGNORE_CALLERS)

      def self.caller_files
        cleaned_caller(1).flatten
      end

      def self.caller_locations
        cleaned_caller 2
      end

      def self.cleaned_caller(keep = 3)
        caller(1).
          map    { |line| line.split(/:(?=\d|in )/, 3)[0,keep] }.
          reject { |file, *_| CALLERS_TO_IGNORE.any? { |pattern| file =~ pattern } }
      end

      def self.app_file
        caller_files.first || $0
      end

  end

  at_exit { Worker.run! if $!.nil? && Worker.run? }
end
