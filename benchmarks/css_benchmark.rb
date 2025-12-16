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

# Sample HTML/XML for CSS selector queries
HTML_DATA = begin
  divs = (1..200).map do |i|
    "<div class=\"content\" id=\"div#{i}\">
        <h2 class=\"title\">Heading #{i}</h2>
        <p class=\"text\">Paragraph #{i} with <span class=\"highlight\">highlighted</span> text.</p>
        <ul class=\"list\">
          <li>Item 1</li>
          <li>Item 2</li>
          <li class=\"special\">Special Item</li>
        </ul>
      </div>"
  end
  "<html><body>#{divs.join}</body></html>"
end

puts "=" * 80
puts "CSS Selector Benchmarks"
puts "=" * 80
puts "Document Size: #{HTML_DATA.bytesize} bytes"
puts

# Parse documents once
rxerces_doc = RXerces::XML::Document.parse(HTML_DATA)
nokogiri_doc = Nokogiri::HTML(HTML_DATA) if NOKOGIRI_AVAILABLE

# Simple CSS selector
puts "Simple CSS: div"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_doc.css('div') }
  x.report("nokogiri") { nokogiri_doc.css('div') } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts

# Class selector
puts "Class CSS: .title"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_doc.css('.title') }
  x.report("nokogiri") { nokogiri_doc.css('.title') } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts

# ID selector
puts "ID CSS: #div100"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_doc.css('#div100') }
  x.report("nokogiri") { nokogiri_doc.css('#div100') } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts

# Descendant combinator
puts "Descendant CSS: div.content p.text"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_doc.css('div.content p.text') }
  x.report("nokogiri") { nokogiri_doc.css('div.content p.text') } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts

# at_css (first match)
puts "at_css: .title (first match only)"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_doc.at_css('.title') }
  x.report("nokogiri") { nokogiri_doc.at_css('.title') } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts
puts "=" * 80
