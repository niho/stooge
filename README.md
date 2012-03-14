Stooge
======

Stooge is a fully EventMachine enabled DSL for interacting with an AMQP broker. Heavily inspired by Minion (but fresher and completely asynchronous).

Setup
-----

Assuming you already have an AMQP broker installed:

    $ gem install stooge

You can configure the address to the broker using the ```AMQP_URL``` environment variable, or programmatically like this:

```ruby
Stooge.amqp_url = 'amqp://johndoe:abc123@localhost/my_vhost'
```

The default if not specified is ```amqp://guest:guest@localhost/```.

Example usage
-------------

To process a job add the following to a file called ```worker.rb``` and run it with ```ruby worker.rb```. Stooge will start an EventMachine loop that waits for AMQP messages and processes matching jobs until you send ```SIG_INT``` or ```SIG_TERM``` to it.

```ruby
require 'stooge'

Stooge.job('example.puts') do |args|
  puts args['message']
end
```

To push a job onto a queue you call ```Stooge.enqueue``` with the name of the work queue and the data you want to process. The data needs to be JSON serializable and can be for example a hash.

```ruby
require 'stooge'

EM.run do
  Stooge.enqueue('example.puts', :message => 'Hello, world!')
end
```

Error handling
--------------

When an error is thrown in a job handler, the job is requeued to be done later and the Stooge process exits. If you define an error handler, however, the error handler is run and the job is removed from the queue.

```ruby
Stooge.error do |e|
  puts "got an error! #{e}"
end
```

Logging
-------

Stooge logs to stdout via ```puts```. You can specify a custom logger like this:

```ruby
Stooge.logger do |msg|
  puts msg
end
```

Testing
-------

To test the business logic in your job handler you can use the ```Stooge.run_handler``` helper method:

```ruby
Stooge.run_handler('example.work', { :foo => 'bar' }).should == 42
```

The return value is the return value from executing the job handler block.

Author
------

Stooge was created by Niklas Holmgren (niklas@sutajio.se) with help from Martin Bruse (@zond) and released under the MIT license. Stooge is very much inspired by Minion (created by Orion Henry), Resque (created by Chris Wanstrath) and Stalker (created by Adam Wiggins).
