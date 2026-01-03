#!/usr/bin/env ruby
# frozen_string_literal: true

# Micro-benchmark isolating XPath validation overhead
#
# This benchmark focuses specifically on measuring the validation
# overhead by using very simple documents and minimal XPath execution time.

require "benchmark/ips"
require "rxerces"

puts "=" * 70
puts "XPath Validation Cache Micro-Benchmarks"
puts "=" * 70
puts
puts "Xalan enabled: #{RXerces.xalan_enabled?}"
puts

# Use a tiny document to minimize XPath execution time
tiny_xml = "<r><a/></r>"
tiny_doc = RXerces::XML::Document.parse(tiny_xml)

# Generate many unique XPath expressions to prevent any caching benefit
def generate_unique_xpaths(count)
  count.times.map { |i| "//a[#{i + 1} = #{i + 1}]" }
end

puts "-" * 70
puts "Test 1: Same expression repeated (cache hit scenario)"
puts "-" * 70
puts

simple_xpath = "//a"

# Clear cache and warm up
RXerces.clear_xpath_validation_cache

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("cached (repeated)") do
    RXerces.cache_xpath_validation = true
    tiny_doc.xpath(simple_xpath)
  end

  x.report("uncached (repeated)") do
    RXerces.cache_xpath_validation = false
    tiny_doc.xpath(simple_xpath)
  end

  x.compare!
end

puts
puts "-" * 70
puts "Test 2: Many unique expressions (cache miss then hit vs always validate)"
puts "-" * 70
puts

unique_xpaths = generate_unique_xpaths(100)
RXerces.clear_xpath_validation_cache

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("cached (100 unique, round-robin)") do |times|
    RXerces.cache_xpath_validation = true
    times.times { |i| tiny_doc.xpath(unique_xpaths[i % 100]) }
  end

  x.report("uncached (100 unique, round-robin)") do |times|
    RXerces.cache_xpath_validation = false
    times.times { |i| tiny_doc.xpath(unique_xpaths[i % 100]) }
  end

  x.compare!
end

puts
puts "-" * 70
puts "Test 3: Pure validation overhead measurement (validation-only calls)"
puts "-" * 70
puts

# Measure how long validation itself takes by comparing many XPath calls
# with a small vs large expression (validation time scales with expression length)

short_xpath = "//a"
long_xpath = "//a[@x='1' and @y='2' and @z='3'][position() > 0 and position() < 100][contains(text(), 'test')]"

RXerces.clear_xpath_validation_cache

puts "Short XPath: #{short_xpath.length} chars"
puts "Long XPath: #{long_xpath.length} chars"
puts

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("short xpath (cached)") do
    RXerces.cache_xpath_validation = true
    tiny_doc.xpath(short_xpath)
  end

  x.report("short xpath (uncached)") do
    RXerces.cache_xpath_validation = false
    tiny_doc.xpath(short_xpath)
  end

  x.report("long xpath (cached)") do
    RXerces.cache_xpath_validation = true
    tiny_doc.xpath(long_xpath)
  end

  x.report("long xpath (uncached)") do
    RXerces.cache_xpath_validation = false
    tiny_doc.xpath(long_xpath)
  end

  x.compare!
end

puts
puts "-" * 70
puts "Test 4: High-frequency scenario (10,000 queries, same expression)"
puts "-" * 70
puts

RXerces.clear_xpath_validation_cache
iterations = 10_000

require "benchmark"

puts "Running #{iterations} XPath queries..."
puts

RXerces.cache_xpath_validation = true
RXerces.clear_xpath_validation_cache
cached_time = Benchmark.realtime do
  iterations.times { tiny_doc.xpath(simple_xpath) }
end

RXerces.cache_xpath_validation = false
uncached_time = Benchmark.realtime do
  iterations.times { tiny_doc.xpath(simple_xpath) }
end

puts "With cache:    #{cached_time.round(4)}s (#{(iterations / cached_time).round(1)} queries/sec)"
puts "Without cache: #{uncached_time.round(4)}s (#{(iterations / uncached_time).round(1)} queries/sec)"
puts "Difference:    #{((uncached_time - cached_time) * 1000).round(2)}ms (#{((uncached_time / cached_time - 1) * 100).round(2)}% overhead)"

puts
puts "-" * 70
puts "Cache statistics"
puts "-" * 70
puts

RXerces.cache_xpath_validation = true
RXerces.clear_xpath_validation_cache

# Populate with test expressions
unique_xpaths.each { |xp| tiny_doc.xpath(xp) }

puts "Expressions cached: #{RXerces.xpath_validation_cache_size}"
puts "Max cache size: #{RXerces.xpath_validation_cache_max_size}"
puts
puts "=" * 70
puts "Benchmark complete!"
