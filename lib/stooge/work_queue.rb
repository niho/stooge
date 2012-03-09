module Stooge
  module WorkQueue

    # Push a job onto a named queue.
    #
    # jobs    - The name of a work queue or an array of names that the job
    #           will be sent through in sequential order (a workflow).
    # data    - The data to send as input to the job. Needs to be JSON
    #           serializable.
    # headers - AMQP headers to include in the job that gets pushed. Needs to
    #           be a hash with key/value pairs.
    #
    # Yields when the job has been put onto the queue, if a block is given.
    #
    # Examples
    #
    #   Stooge.enqueue('example.work')
    #
    #   Stooge.enqueue(['make.sandwich', 'eat.sandwich'], 'for' => 'me')
    #
    # Returns nothing.
    def enqueue(jobs, data = {}, headers = {}, &block)
      Fiber.new do
        EM::Synchrony.sync aenqueue(jobs, data, headers, &block)
      end.resume
    end

    # Asynchrounous version of enqueue.
    #
    # jobs    - The name of a work queue or an array of names that the job
    #           will be sent through in sequential order (a workflow).
    # data    - The data to send as input to the job. Needs to be JSON
    #           serializable.
    # headers - AMQP headers to include in the job that gets pushed. Needs to
    #           be a hash with key/value pairs.
    #
    # Yields when the job has been put onto the queue, if a block is given.
    #
    # Returns an EM::DefaultDeferrable object.
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
      log "send: #{queue}:#{encoded}"

      exchange = amqp_channel.direct('')
      deferrable = EM::DefaultDeferrable.new
      exchange.publish(encoded, headers.merge(:routing_key => queue)) do
        block.call unless block.nil?
        deferrable.set_deferred_status :succeeded
      end
      deferrable
    end

    # Creates a job handler for a named queue.
    # 
    # queue   - The name of the work queue.
    # options - Options for how the handler processes jobs (default: {}):
    #           :when - If you want a worker to only subscribe to a queue
    #                   under specific conditions this parameter takes a
    #                   lambda as an argument. If the lambda returns true
    #                   the job will be performed.
    #
    # Examples
    #
    #   Stooge.job('example.work') do |args,headers|
    #     # Do the work here...
    #   end
    #
    # Returns nothing.
    def job(queue, options = {}, &blk)
      handler = Stooge::Handler.new(queue)
      handler.when = options[:when] if options[:when]
      handler.unsub = lambda do |channel|
        log "unsubscribing to #{queue}"
        channel.queue(queue, :durable => true, :auto_delete => false).unsubscribe
      end
      handler.sub = lambda do |channel|
        log "subscribing to #{queue}"
        channel.queue(queue, :durable => true, :auto_delete => false).subscribe(:ack => true) do |h,m|
          unless AMQP.closing?
            begin
              log "recv: #{queue}:#{m}"

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
      add_handler(handler)
    end

  end
end
