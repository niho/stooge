require 'uri'
require 'multi_json'
require 'amqp'
require 'em-synchrony'
require 'stooge/version'
require 'stooge/handler'
require 'stooge/work_queue'
require 'stooge/pubsub'
require 'stooge/rpc'
require 'stooge/worker'

module Stooge
  extend self
  extend Stooge::WorkQueue
  extend Stooge::Pubsub
  extend Stooge::Rpc

  def amqp_url
    @@amqp_url ||= ENV["AMQP_URL"] || "amqp://guest:guest@localhost/"
  end

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

  def check_all(channel)
    @@handlers ||= []
    @@handlers.each { |h| h.check(channel) }
  end

  def add_handler(handler)
    @@handlers ||= []
    @@handlers << handler
  end

  def handlers?
    @@handlers ||= []
    @@handlers.empty? == false
  end

  def start
    AMQP.start(amqp_config) do |connection|
      AMQP::Channel.new(connection) do |channel|
        channel.prefetch(1)
        check_all(channel)
      end
    end
  end

  def work_one_job
    AMQP::Channel.new(amqp_connection) do |channel|
      channel.prefetch(1)
      check_all(channel)
      return
    end
  end

  private

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

    def amqp_connection
      @@amqp_connection ||= AMQP.connect(amqp_config)
    end

    def amqp_channel
      @@amqp_channel ||= AMQP::Channel.new(amqp_connection)
    end

    def next_job(args, response)
      queue = args.delete("next_job")
      enqueue(queue,args.merge(response)) if queue and not queue.empty?
    end

    def error_handler
      @@error_handler ||= nil
    end

end
