#!/usr/bin/env ruby
# frozen_string_literal: true

# Dependency-free benchmark for overhead in the Ruby bindings. Run against the
# same Ruby and Xerces builds before and after a change; compare median times.
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rxerces'
require 'benchmark'
require 'json'

duration = Float(ENV.fetch('BENCH_TIME', '0.1'))
raise 'BENCH_TIME must be positive' unless duration.positive? && duration.finite?

results = { ruby: RUBY_DESCRIPTION, xalan: RXerces.xalan_enabled?, measurements: [] }
[100, 1_000, 10_000].each do |count|
  xml = "<root>#{'<item id="1"><name>Hello</name></item>' * count}</root>"
  doc = RXerces.XML(xml)
  root = doc.root
  operations = {
    parse: -> { RXerces.XML(xml) },
    children: -> { root.children },
    element_children: -> { root.element_children },
    first_element_child: -> { root.first_element_child },
    last_element_child: -> { root.last_element_child },
    xpath: -> { doc.xpath('//item') },
    at_xpath: -> { doc.at_xpath('//item') },
    text: -> { root.text },
    serialize: -> { doc.to_xml }
  }

  operations.each do |name, operation|
    operation.call # Warm lazy initialization and expression caches.
    iterations = 1
    loop do
      elapsed = Benchmark.realtime { iterations.times { operation.call } }
      break if elapsed >= duration
      iterations *= 2
    end
    samples = Array.new(3) do
      GC.start
      Benchmark.realtime { iterations.times { operation.call } } / iterations
    end
    GC.start
    allocated = GC.stat(:total_allocated_objects)
    operation.call
    allocated = GC.stat(:total_allocated_objects) - allocated
    results[:measurements] << {
      elements: count, operation: name, microseconds: samples.sort[1] * 1_000_000,
      ruby_allocations: allocated
    }
  end
end
puts JSON.pretty_generate(results)
