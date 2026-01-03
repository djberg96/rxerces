#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark comparing XPath performance with and without validation caching
#
# This benchmark measures the overhead of XPath expression validation
# and demonstrates the performance benefit of caching validated expressions.

require "benchmark/ips"
require "rxerces"

puts "=" * 70
puts "XPath Validation Cache Benchmarks"
puts "=" * 70
puts

# Build a moderately sized document
def build_xml(num_items)
  items = (1..num_items).map do |i|
    category = %w[fiction science history biography].sample
    <<~ITEM
      <item id="#{i}" category="#{category}">
        <title>Item #{i}</title>
        <price>#{(rand * 50).round(2)}</price>
        <stock>#{rand(100)}</stock>
      </item>
    ITEM
  end.join("\n")

  <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <catalog>
      #{items}
    </catalog>
  XML
end

xml = build_xml(500)
doc = RXerces::XML::Document.parse(xml)

puts "Document size: #{xml.bytesize} bytes"
puts "Xalan enabled: #{RXerces.xalan_enabled?}"
puts

# Define various XPath expressions to test
xpath_expressions = [
  "//item",
  "//item[@category='fiction']",
  "//item/title",
  "//item[price > 25]",
  "//item[@id='100']",
  "/catalog/item[1]",
  "//item[contains(title, 'Item')]",
  "//item[stock < 50]/title",
]

puts "-" * 70
puts "Single XPath expression, repeated queries (same expression)"
puts "-" * 70
puts

single_xpath = "//item[@category='fiction']"

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("with cache (default)") do
    RXerces.cache_xpath_validation = true
    doc.xpath(single_xpath)
  end

  x.report("without cache") do
    RXerces.cache_xpath_validation = false
    doc.xpath(single_xpath)
  end

  x.compare!
end

# Reset to default
RXerces.cache_xpath_validation = true
RXerces.clear_xpath_validation_cache

puts
puts "-" * 70
puts "Multiple different XPath expressions (round-robin)"
puts "-" * 70
puts

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("with cache") do |times|
    RXerces.cache_xpath_validation = true
    times.times do |i|
      doc.xpath(xpath_expressions[i % xpath_expressions.length])
    end
  end

  x.report("without cache") do |times|
    RXerces.cache_xpath_validation = false
    times.times do |i|
      doc.xpath(xpath_expressions[i % xpath_expressions.length])
    end
  end

  x.compare!
end

# Reset
RXerces.cache_xpath_validation = true
RXerces.clear_xpath_validation_cache

puts
puts "-" * 70
puts "High-volume scenario: 1000 queries with same expression"
puts "-" * 70
puts

iterations = 1000
test_xpath = "//item[price > 20]"

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("with cache (1000 queries)") do
    RXerces.cache_xpath_validation = true
    iterations.times { doc.xpath(test_xpath) }
  end

  x.report("without cache (1000 queries)") do
    RXerces.cache_xpath_validation = false
    iterations.times { doc.xpath(test_xpath) }
  end

  x.compare!
end

# Reset
RXerces.cache_xpath_validation = true
RXerces.clear_xpath_validation_cache

puts
puts "-" * 70
puts "Cache statistics after benchmark"
puts "-" * 70
puts

# Run some queries to populate cache
xpath_expressions.each { |xp| doc.xpath(xp) }

puts "Cache size: #{RXerces.xpath_validation_cache_size}"
puts "Cache max size: #{RXerces.xpath_validation_cache_max_size}"
puts "Cache enabled: #{RXerces.cache_xpath_validation?}"
puts
puts "=" * 70
puts "Benchmark complete!"
