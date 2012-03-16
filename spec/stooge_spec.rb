dir = File.dirname(File.expand_path(__FILE__))
$LOAD_PATH.unshift dir + '/../lib'

require 'stooge'
require 'rspec'

describe Stooge do

  before do
    Stooge.amqp_url = 'amqp://guest:guest@localhost/'
    Stooge.clear_handlers
  end

  it 'should use a default URL to the AMQP broker' do
    Stooge.amqp_url.should == 'amqp://guest:guest@localhost/'
    Stooge.send(:amqp_config).should == {
      :vhost => '/',
      :host => 'localhost',
      :user => 'guest',
      :port => 5672,
      :pass => 'guest'
    }
  end

  it 'should be possible to configure the URL to the AMQP broker' do
    Stooge.amqp_url = 'amqp://john:doe@example.com:5000/vhost'
    Stooge.amqp_url.should == 'amqp://john:doe@example.com:5000/vhost'
    Stooge.send(:amqp_config).should == {
      :vhost => '/vhost',
      :host => 'example.com',
      :user => 'john',
      :port => 5000,
      :pass => 'doe'
    }
  end

  it 'can add a job handler (ruby block) for a specified work queue' do
    Stooge.job('test.work') {}
    Stooge.should have_handlers
  end

  it 'can enqueue jobs on a named queue with data and headers if inside an EM synchrony block' do
    EM.synchrony do
      # Here we stub the call to #publish on the default exchange and
      # intercept the published message instead of sending the message to the
      # broker and then testing if the broker receieved a new message, which
      # is very hard to do reliably because of timing issues and because the
      # message is silently dropped by the broker if no queue is bound to the
      # exchange. It also give us the ability to easily test that the message
      # is published with the correct options.
      Stooge.with_channel do |channel|
        channel.default_exchange.should_receive(:publish).with(
          '{"test":"test"}',
          {
            :routing_key => 'test.work',
            :mandatory => true,
            :content_type => 'application/json',
            :headers => { :foo => 'bar' }
          }).and_yield
      end
      Stooge.enqueue('test.work', { :test => 'test' }, :foo => 'bar')
      Stooge.stop!
    end
  end

  it 'can put a job on a queue and that job is the later picked up by a handler and processed' do
    # This test is a bit tricky and might require some explanation. To
    # actually test that this works we need to first create a job handler that
    # sets a global ($work_performed) variable that we can later check to see
    # wether the job has actually been performed. We then open an EM synchrony
    # block in which we start the job handler (i.e. makes it listen to its
    # queue for job messages). We then enqeue a job and later check if the job
    # was performed as expected.
    #
    # To make all this work we need to deal with some nasty timing issues:
    #
    # 1. We need make sure the handler has had enough time to create a queue
    #    and binding before we can publish a message, or the message will
    #    just be silently dropped. This needs to happen in different EM tick.
    #    We therefor add an EM timer to publish the message 1 second later.
    #    The timer requires us to open up yet another synchrony block, because
    #    the timer block does not execute inside the fiber created by
    #    synchrony which it needs to do for Stooge#enqueue to work (because of
    #    the deferable magic happening behind the scenes).
    #
    # 2. When we have published the message we then need to wait a while for
    #    the job handler to pick it up and process it. We need to keep the
    #    EM loop alive for this to happen, so we simply sleep for 1 second
    #    before we shut the EM loop down and check if the job was processed.
    # 
    # NOTE: This all depend on the communication with the broker taking less
    # than 1 second, which should be more than fine in most cases. If this
    # test stops working for some reason the first thing to try should be to
    # increase the wait time and see if it works then.
    #
    $work_performed = false
    Stooge.job('test.work') { $work_performed = true }
    EM.synchrony do
      Stooge.with_channel do |channel|
        Stooge.start_handlers(channel)
      end
      EM.add_timer(1) do
        EM.synchrony do
          Stooge.enqueue('test.work', { :test => 'test' }, :foo => 'bar')
        end
        sleep(1)
        Stooge.stop!
      end
    end
    $work_performed.should == true
  end

  it 'should be possible to specify a custom global error handler' do
    $error = false
    old_handler = Stooge.error_handler
    Stooge.error do |exception, handler, payload, metadata|
      $error = true
    end
    Stooge.job('test.work') { raise }
    Stooge.run_handler('test.work', '')
    Stooge.error(&old_handler)
    $error.should == true
  end

  it 'should be possible to specify a custom logger' do
    $logged = false
    old_logger = Stooge.logger
    Stooge.logger do |msg|
      $logged = true
    end
    Stooge.log('test')
    Stooge.logger(&old_logger)
    $logged.should == true
  end

  it 'should be possible to test a handler' do
    $work_performed = false
    Stooge.job('test.work') do |args, headers|
      $work_performed = true
      args.should == { 'test' => 'test' }
      headers.should == { :foo => 'bar' }
    end
    Stooge.run_handler('test.work', { :test => 'test' }, :foo => 'bar')
    $work_performed.should == true
  end

end
