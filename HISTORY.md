
### 0.1.1 (2012-03-16)

* Added a test suite

### 0.1.0 (2012-03-14)

* Implemented same basic feature set as Minion (i.e. work queues)
* Added ability to easily test job handlers
* Made both #enqueue and #job asynchronous
* Changed from using Bunny to the using official AMQP gem
* Improved error handling logic and logging
* Handling of message content types (JSON is still default)
* Added reconnect to broker on connection failure support
