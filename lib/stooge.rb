require 'uri'
require 'multi_json'
require 'amqp'
require 'em-synchrony'
require 'stooge/version'
require 'stooge/handler'
require 'stooge/work_queue'
require 'stooge/worker'

module Stooge
  extend self
  extend Stooge::WorkQueue

  @@connection = nil
  @@channel = nil
  @@handlers = []
  @@error_handler = Proc.new do |exception, handler, payload, metadata|
    Stooge.log "#{handler.queue_name} failed: #{exception.inspect}"
    raise exception
  end

  #
  # Will return a URL to the AMQP broker to use. Will get this from the
  # <code>ENV</code> variable <code>AMQP_URL</code> if present, or use the
  # default which is "amqp://guest:guest@localhost/" (the same as the default
  # for a local RabbitMQ install).
  #
  # @return [String] a URL to an AMQP broker.
  #
  def amqp_url
    @@amqp_url ||= ENV["AMQP_URL"] || "amqp://guest:guest@localhost/"
  end

  #
  # Set the URL to the AMQP broker to use. The format of the URL should be
  # "amqp://username:password@hostname/vhost" (vhost and username/password is
  # optional).
  #
  def amqp_url=(url)
    @@amqp_url = url
  end

  #
  # Log message using the Stooge logger.
  #
  # @param [String] msg the message to log.
  #
  def log(msg)
    @@logger ||= proc { |m| puts "#{Time.now} :stooge: #{m}" }
    @@logger.call(msg)
  end

  #
  # Configure a custom logger for Stooge. The block gets yielded with the
  # log message. You can do whatever you want with it. The default behaviour
  # is to simply output to stdout.
  #
  # @param [Proc] block a {::Proc} to yield when a message needs to be logged.
  # @yieldparam [String] msg the message to log.
  #
  def logger(&blk)
    @@logger = blk
  end

  #
  # Configure a global error handler for Stooge jobs. The block gets yielded
  # when a job handler raises an exception. The default error handler simply
  # logs the error and re-raises the exception. You can use this to for
  # example re-queue a failed job or send email notifications when a job
  # fails.
  #
  # If you don't raise an exception in the error handler the job will be
  # acked with the broker and the broker will consider the job done and remove
  # it from the queue. If you for some reason want to force the job to be
  # acked even when you raise an error you can manually ack it before you
  # raise the error, like this:
  #
  #   Stooge.error do |exception, handler, payload, metadata|
  #     metadata.ack
  #     raise exception
  #   end
  #
  # @param [Proc] block a {::Proc} to yield when an error happens.
  # @yieldparam [Exception] exception the exception object raised.
  # @yieldparam [Stooge::Handler] handler the handler that failed.
  # @yieldparam [Object] payload the message payload that was processed when
  #   the handler failed.
  # @yieldparam [Hash] metadata the message metadata (headers, etc.)
  #
  def error(&blk)
    @@error_handler = blk
  end

  #
  # The global error handler.
  #
  # @return [Proc] the error handler block.
  # 
  def error_handler
    @@error_handler
  end

  #
  # Start listening to for new jobs on all queues using the specified channel.
  #
  # @param [AMQP::Channel] channel an open AMQP channel
  #
  def start_handlers(channel)
    @@handlers.each { |h| h.start(channel) }
  end

  #
  # Add a new job handler. Used by {Stooge.job}.
  # 
  # @param [Stooge::Handler] handler a handler object
  #
  def add_handler(handler)
    @@handlers << handler
  end

  #
  # Are there any job handlers defined? Used by {Stooge::Worker} to check if
  # it should start a worker process.
  #
  # @return [Boolean] true or false
  #
  def handlers?
    @@handlers.empty? == false
  end

  #
  # Execute a handler block without going through AMQP at all. This is a
  # helper method for use in tests. It allows you to test the business logic
  # in a handler block without having to mess with the details of how Stooge
  # works internally.
  #
  # Examples
  #
  #   Stooge.run_handler('example.work', :foo => 'bar').should == 42
  #
  # @param [String] queue_name the name of the handler to run
  # @param [Object] data message data to send to the handler as arguments
  # @param [Hash] headers optional headers to send as second argument to the
  #   handler block
  #
  # @return the return value of the handler block
  #
  def run_handler(queue_name, data, headers = {})
    @@handlers.each do |handler|
      if handler.queue_name == queue_name
        return handler.block.call(data, headers)
      end
    end
  end

  #
  # Will yield an open and ready connection.
  #
  # @param [Proc] block a {::Proc} to yield an open and ready connection to.
  #
  def with_connection(&block)
    if @@connection.nil? || @@connection.status == :closed
      @@connection = AMQP.connect(amqp_config)
      @@connection.on_tcp_connection_loss do
        Stooge.log "[network failure] trying to reconnect..."
        @@connection.reconnect
      end
      @@connection.on_recovery do
        Stooge.log "connection with broker recovered"
      end
      @@connection.on_error do |ch, connection_close|
         raise connection_close.reply_text
       end
    end
    @@connection.on_open do
      yield @@connection
    end
  end

  #
  # Will yield an open and ready channel.
  #
  # @param [Proc] block a {::Proc} to yield an open and ready channel to.
  #
  def with_channel(&block)
    with_connection do |connection|
      if @@channel.nil? || @@channel.status == :closed
        @@channel = AMQP::Channel.new(connection, AMQP::Channel.next_channel_id, channel_options)
        @@channel.on_error do |ch, channel_close|
          Stooge.log "channel-level exception: code = #{channel_close.reply_code}, message = #{channel_close.reply_text}"
        end
      end
      @@channel.once_open do
        yield @@channel
      end
    end
  end

  # Start a {::Stooge} worker that consumes messages from the AMQP broker.
  def start!
    EM.synchrony do
      with_channel do |channel|
        start_handlers(channel)
      end
    end
  end

  # Will stop and deactivate {::Stooge}.
  def stop!
    EM.next_tick do
      with_channel do |channel|
        channel.close
      end
      @@channel = nil
      with_connection do |connection|
        connection.close
      end
      @@connection = nil
      EM.stop
    end
  end

  private

    # Will return the default options to use when creating channels.
    def channel_options
      @channel_options ||= {
        :prefetch => 1,
        :auto_recovery => true
      }
    end

    # Will return the default options when connecting to the AMQP broker.
    # Uses the URL from {#amqp_url} to construct these options.
    def amqp_config
      uri = URI.parse(amqp_url)
      {
        :vhost => uri.path,
        :host => uri.host,
        :user => uri.user,
        :port => (uri.port || 5672),
        :pass => uri.password
      }
    rescue Object => e
      raise "invalid AMQP_URL: #{uri.inspect} (#{e})"
    end

end
