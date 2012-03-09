#!/usr/bin/env ruby

$: << File.join(File.dirname(__FILE__), "..", "lib")

require 'stooge'

Stooge.job($1 || "jobs") do |job|
  puts "consumed #{job.inspect}"
end
