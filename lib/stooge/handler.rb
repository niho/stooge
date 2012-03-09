module Stooge
  class Handler

    attr_accessor :queue, :sub, :unsub, :when, :on

    def initialize(queue)
      @queue = queue
      @when = lambda { true }
      @sub = lambda {}
      @unsub = lambda {}
      @on = false
    end

    def should_sub?
      @when.call
    end

    def unsubscribe!
      @when = lambda { false }
    end

    def check(channel)
      if should_sub?
        @sub.call(channel) unless @on
        @on = true
      else
        @unsub.call(channel) if @on
        @on = false
      end
    end

    def to_s
      "<handler queue=#{@queue} on=#{@on}>"
    end

  end
end
