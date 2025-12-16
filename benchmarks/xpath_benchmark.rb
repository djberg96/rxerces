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

# Sample XML for XPath queries
XML_DATA = begin
  books = (1..500).map do |i|
    category = ['fiction', 'science', 'biography', 'history'][i % 4]
    year = 1990 + (i % 30)
    price = 10.0 + (i % 50)
    "<book id=\"book#{i}\" category=\"#{category}\">
      <title lang=\"en\">Title #{i}</title>
      <author>Author #{i}</author>
      <year>#{year}</year>
      <price>#{'%.2f' % price}</price>
    </book>"
  end
  "<catalog>#{books.join}</catalog>"
end

puts "=" * 80
puts "XPath Query Benchmarks"
puts "=" * 80
puts "XML Size: #{XML_DATA.bytesize} bytes"
puts

# Parse documents once
rxerces_doc = RXerces::XML::Document.parse(XML_DATA)
nokogiri_doc = Nokogiri::XML(XML_DATA) if NOKOGIRI_AVAILABLE

# Simple XPath queries
puts "Simple XPath: //book"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_doc.xpath('//book') }
  x.report("nokogiri") { nokogiri_doc.xpath('//book') } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts

# Attribute-based XPath queries
puts "Attribute XPath: //book[@category='fiction']"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_doc.xpath("//book[@category='fiction']") }
  x.report("nokogiri") { nokogiri_doc.xpath("//book[@category='fiction']") } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts

# Complex XPath queries
puts "Complex XPath: //book[year > 2000 and price < 30]/title"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_doc.xpath('//book[year > 2000 and price < 30]/title') }
  x.report("nokogiri") { nokogiri_doc.xpath('//book[year > 2000 and price < 30]/title') } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts

# at_xpath (first match)
puts "at_xpath: //book (first match only)"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_doc.root.at_xpath('//book') }
  x.report("nokogiri") { nokogiri_doc.at_xpath('//book') } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts
puts "=" * 80
