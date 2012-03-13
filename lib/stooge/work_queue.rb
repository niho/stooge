module Stooge
  module WorkQueue

    # Push a job onto a named queue.
    #
    # queue_name - The name of a work queue or an array of names that the job
    #              will be sent through in sequential order (a workflow).
    # data       - The data to send as input to the job. Needs to be JSON
    #              serializable.
    # headers    - AMQP headers to include in the job that gets pushed. Needs
    #              to be a hash with key/value pairs.
    #
    # Examples
    #
    #   Stooge.enqueue('example.work')
    #
    # Returns nothing.
    def enqueue(queue_name, data, headers = {})
      EM::Synchrony.sync(aenqueue(queue_name, data, headers))
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
    def aenqueue(queue_name, data, headers = {})
      deferrable = EM::DefaultDeferrable.new
      with_channel do |channel|
        options = {
          :routing_key => queue_name,
          :mandatory => true,
          :content_type => 'application/json',
          :headers => headers
        }
        channel.default_exchange.publish(MultiJson.encode(data), options) do
          Stooge.log("enqueue: #{queue_name}(#{data})")
          yield if block_given?
          deferrable.set_deferred_status :succeeded
        end
      end
      deferrable
    end

    # Creates a job handler for a named queue.
    # 
    # queue   - The name of the work queue.
    #
    # Examples
    #
    #   Stooge.job('example.work') do |args,headers|
    #     # Do the work here...
    #   end
    #
    # Returns nothing.
    def job(queue, &blk)
      handler = Stooge::Handler.new(queue, :queue_options => { :durable => true })
      handler.block = blk
      add_handler(handler)
    end

  end
end
