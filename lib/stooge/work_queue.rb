module Stooge
  module WorkQueue

    def enqueue(jobs, data = {}, headers = {}, &block)
      EM::Synchrony.sync aenqueue(jobs, data, headers, &block)
    end

    def aenqueue(jobs, data = {}, headers = {}, &block)
      raise "cannot enqueue a nil job" if jobs.nil?
      raise "cannot enqueue an empty job" if jobs.empty?

      ## jobs can be one or more jobs
      if jobs.respond_to? :shift
        queue = jobs.shift
        data["next_job"] = jobs unless jobs.empty?
      else
        queue = jobs
      end

      encoded = MultiJson.encode(data)

      deferrable = EM::DefaultDeferrable.new
      amqp_channel do
        amqp_channel.direct('') do |exchange|
          exchange.publish(encoded, headers.merge(:routing_key => queue)) do
            block.call unless block.nil?
            deferrable.set_deferred_status :succeeded
          end
        end
      end
      deferrable
    end

    def job(queue, options = {}, &blk)
      handler = Stooge::Handler.new(queue)
      handler.when = options[:when] if options[:when]
      handler.unsub = lambda do |channel|
        log "unsubscribing to #{queue}"
        channel.queue(queue, :durable => true, :auto_delete => false).unsubscribe
      end
      handler.sub = lambda do |channel|
        channel.queue(queue, :durable => true, :auto_delete => false) do |queue|
          queue.subscribe(:ack => true) do |h,m|
            unless channel.connection.closing?
              begin
                
                args = MultiJson.decode(m)
                
                result = yield(args,h)
                
                next_job(args, result)
              rescue Object => e
                raise unless error_handler
                error_handler.call(e,queue,m,h)
              end
              h.ack
              check_all(channel)
            end
          end
        end
      end
      add_handler(handler)
    end

  end
end
