#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark/ips'
require 'rxerces'

begin
  require 'nokogiri'
  NOKOGIRI_AVAILABLE = true
rescue LoadError
  NOKOGIRI_AVAILABLE = false
  puts "Nokogiri not available - install with: gem install nokogiri"
end

puts "=" * 80
puts "Document Serialization Benchmarks"
puts "=" * 80
puts

# Small document
SMALL_XML = <<~XML
  <root>
    <person id="1" name="Alice">
      <age>30</age>
      <city>New York</city>
    </person>
  </root>
XML

rxerces_small = RXerces::XML::Document.parse(SMALL_XML)
nokogiri_small = Nokogiri::XML(SMALL_XML) if NOKOGIRI_AVAILABLE

puts "Small document to_s (#{SMALL_XML.bytesize} bytes)"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_small.to_s }
  x.report("nokogiri") { nokogiri_small.to_xml } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts

# Medium document
def generate_xml(count)
  people = (1..count).map do |i|
    "<person id=\"#{i}\" name=\"Person#{i}\"><age>#{20 + (i % 50)}</age><city>City#{i % 20}</city></person>"
  end
  "<root>#{people.join}</root>"
end

MEDIUM_XML = generate_xml(100)

rxerces_medium = RXerces::XML::Document.parse(MEDIUM_XML)
nokogiri_medium = Nokogiri::XML(MEDIUM_XML) if NOKOGIRI_AVAILABLE

puts "Medium document to_s (#{MEDIUM_XML.bytesize} bytes)"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_medium.to_s }
  x.report("nokogiri") { nokogiri_medium.to_xml } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts

# Large document
LARGE_XML = generate_xml(1000)

rxerces_large = RXerces::XML::Document.parse(LARGE_XML)
nokogiri_large = Nokogiri::XML(LARGE_XML) if NOKOGIRI_AVAILABLE

puts "Large document to_s (#{LARGE_XML.bytesize} bytes)"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_large.to_s }
  x.report("nokogiri") { nokogiri_large.to_xml } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts
puts "=" * 80
