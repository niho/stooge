#!/usr/bin/env ruby

$: << File.join(File.dirname(__FILE__), "..", "lib")

require 'stooge'

Stooge.job("jobs") do |job|
  puts "consumed #{job.inspect}"
end
