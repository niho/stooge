module Stooge
  class Handler

    attr_accessor :queue_name, :queue_options, :block

    def initialize(queue, options = {})
      @queue_name = queue
      @queue_options = options[:queue_options] || {}
      @options = options
      @block = lambda {}
    end

    def start(channel)
      Stooge.log "starting handler for #{@queue_name}"
      channel.queue(@queue_name, @queue_options) do |queue|
        queue.subscribe(:ack => true) do |metadata, payload|
          Stooge.log "recv: #{@queue_name}"
          begin
            case metadata.content_type
            when 'application/json'
              args = MultiJson.decode(payload)
            else
              args = payload
            end
            @block.call(args, metadata.headers)
          rescue Object => e
            if Stooge.error_handler
              Stooge.error_handler.call(e,self,payload,metadata)
            end
          end
          metadata.ack
        end
      end
    end

  end
end
