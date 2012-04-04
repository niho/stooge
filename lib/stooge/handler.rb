module Stooge
  class Handler

    attr_accessor :queue_name, :queue_options, :block

    #
    # Create a new handler object.
    #
    # @param [String] queue the name of the queue that this handler will pick
    #   jobs from.
    # @param [Hash] options handler options.
    # @option options [Hash] :queue_options Options to use when creating the
    #   queue.
    #
    def initialize(queue, options = {})
      @queue_name = queue
      @queue_options = options[:queue_options] || {}
      @options = options
      @block = lambda {}
    end

    #
    # Start subscribing to the queue that this handler corresponds to. When
    # a message arive; parse it and call the handler block with the data.
    #
    # @param [AMQP::Channel] channel an open AMQP channel
    #
    def start(channel)
      Stooge.log "starting handler for #{@queue_name}"
      channel.queue(@queue_name, @queue_options) do |queue|
        queue.subscribe(:ack => true) do |metadata, payload|
          Stooge.log "recv: #{@queue_name}"
          run(payload, metadata.content_type, metadata.headers)
          metadata.ack
        end
      end
    end

    #
    # Call the handler block. This method will rescue any exceptions the
    # handler block raises and pass them on to the global error handler.
    #
    # @param [String] payload the message payload
    # @param [String] content_type the MIME content type of the message
    #   payload
    # @param [Hash] headers the message headers
    # 
    # @return [Object] the return value of the handler block
    #
    def run(payload, content_type, headers)
      Fiber.new do
        @block.call(
          decode_payload(payload, content_type),
          headers)
      end.resume
    rescue Object => e
      if Stooge.error_handler
        Stooge.error_handler.call(e,self,payload,headers)
      end
    end

    private

      def decode_payload(payload, content_type)
        case content_type
        when 'application/json'
          MultiJson.decode(payload)
        else
          payload.to_s
        end
      end

  end
end
