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

  def log(msg)
    @@logger ||= proc { |m| puts "#{Time.now} :stooge: #{m}" }
    @@logger.call(msg)
  end

  def logger(&blk)
    @@logger = blk
  end

  def error(&blk)
    @@error_handler = blk
  end

  def error_handler
    @@error_handler
  end

  def start_handlers(channel)
    @@handlers ||= []
    @@handlers.each { |h| h.start(channel) }
  end

  def add_handler(handler)
    @@handlers ||= []
    @@handlers << handler
  end

  def handlers?
    @@handlers ||= []
    @@handlers.empty? == false
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
