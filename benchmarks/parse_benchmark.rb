#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark/ips'
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'rxerces'

# Try to load Nokogiri and Ox
begin
  require 'nokogiri'
  NOKOGIRI_AVAILABLE = true
rescue LoadError
  NOKOGIRI_AVAILABLE = false
  puts "Nokogiri not available - install with: gem install nokogiri"
end

begin
  require 'ox'
  OX_AVAILABLE = true
rescue LoadError
  OX_AVAILABLE = false
  puts "Ox not available - install with: gem install ox"
end

# Sample XML documents of varying sizes
SMALL_XML = <<~XML
  <root>
    <person id="1" name="Alice">
      <age>30</age>
      <city>New York</city>
    </person>
  </root>
XML

MEDIUM_XML = begin
  people = (1..100).map do |i|
    "<person id=\"#{i}\" name=\"Person#{i}\"><age>#{20 + (i % 50)}</age><city>City#{i % 20}</city></person>"
  end
  "<root>#{people.join}</root>"
end

# Generate a large XML document
def generate_large_xml(count = 1000)
  people = (1..count).map do |i|
    "<person id=\"#{i}\" name=\"Person#{i}\"><age>#{20 + (i % 50)}</age><city>City#{i % 20}</city></person>"
  end
  "<root>#{people.join}</root>"
end

LARGE_XML = generate_large_xml(1000)

puts "=" * 80
puts "XML Parsing Benchmarks"
puts "=" * 80
puts

# Small XML parsing
puts "Small XML Parsing (#{SMALL_XML.bytesize} bytes)"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { RXerces::XML::Document.parse(SMALL_XML) }
  x.report("rxerces (fast)") { RXerces::XML::Document.parse(SMALL_XML, fast_parse: true) }
  x.report("nokogiri") { Nokogiri::XML(SMALL_XML) } if NOKOGIRI_AVAILABLE
  x.report("ox") { Ox.parse(SMALL_XML) } if OX_AVAILABLE

  x.compare!
end

puts

# Medium XML parsing
puts "Medium XML Parsing (#{MEDIUM_XML.bytesize} bytes)"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { RXerces::XML::Document.parse(MEDIUM_XML) }
  x.report("rxerces (fast)") { RXerces::XML::Document.parse(MEDIUM_XML, fast_parse: true) }
  x.report("nokogiri") { Nokogiri::XML(MEDIUM_XML) } if NOKOGIRI_AVAILABLE
  x.report("ox") { Ox.parse(MEDIUM_XML) } if OX_AVAILABLE

  x.compare!
end

puts

# Large XML parsing
puts "Large XML Parsing (#{LARGE_XML.bytesize} bytes)"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { RXerces::XML::Document.parse(LARGE_XML) }
  x.report("rxerces (fast)") { RXerces::XML::Document.parse(LARGE_XML, fast_parse: true) }
  x.report("nokogiri") { Nokogiri::XML(LARGE_XML) } if NOKOGIRI_AVAILABLE
  x.report("ox") { Ox.parse(LARGE_XML) } if OX_AVAILABLE

  x.compare!
end

puts
puts "=" * 80
