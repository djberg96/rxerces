#!/usr/bin/env ruby
# frozen_string_literal: true

# Use the same generated XML as native_parse_benchmark.cpp to separate the
# cost of the Ruby API from parsing in Xerces itself.
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rxerces'
require 'benchmark'
require 'json'

results = { ruby: RUBY_DESCRIPTION, xalan: RXerces.xalan_enabled?, measurements: [] }
[1, 100, 1_000, 10_000].each do |count|
  xml = "<root>#{'<item id="1"><name>Hello</name></item>' * count}</root>"
  iterations = [5_000, 100_000 / count].min
  5.times { RXerces::XML::Document.parse(xml) }
  samples = Array.new(5) do
    GC.start
    elapsed = Benchmark.realtime do
      iterations.times { RXerces::XML::Document.parse(xml) }
    end
    GC.start
    elapsed * 1_000_000 / iterations
  end
  results[:measurements] << {
    elements: count, bytes: xml.bytesize, iterations: iterations,
    median_microseconds: samples.sort[2], samples_microseconds: samples
  }
end
puts JSON.pretty_generate(results)
