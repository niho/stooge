#!/usr/bin/env ruby

$: << File.join(File.dirname(__FILE__), "..", "lib")

require 'stooge'

EM.synchrony do
  10.times do
    Stooge.enqueue("jobs", {"time" => Time.now.to_s})
    EM::Synchrony.sleep 0.5
  end
  EM.stop
end
