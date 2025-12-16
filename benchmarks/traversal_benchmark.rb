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

# Sample XML for DOM traversal
XML_DATA = begin
  sections = (1..100).map do |i|
    "<section id=\"s#{i}\">
      <article id=\"a#{i}\">
        <header>
          <title>Title #{i}</title>
          <author>Author #{i}</author>
        </header>
        <content>
          <paragraph>Paragraph 1</paragraph>
          <paragraph>Paragraph 2</paragraph>
          <paragraph>Paragraph 3</paragraph>
        </content>
        <footer>
          <date>2024-01-01</date>
        </footer>
      </article>
    </section>"
  end
  "<root>#{sections.join}</root>"
end

puts "=" * 80
puts "DOM Traversal Benchmarks"
puts "=" * 80
puts "Document Size: #{XML_DATA.bytesize} bytes"
puts

# Parse documents once
rxerces_doc = RXerces::XML::Document.parse(XML_DATA)
nokogiri_doc = Nokogiri::XML(XML_DATA) if NOKOGIRI_AVAILABLE

rxerces_root = rxerces_doc.root
nokogiri_root = nokogiri_doc.root if NOKOGIRI_AVAILABLE

# Children access
puts "Access .children"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_root.children }
  x.report("nokogiri") { nokogiri_root.children } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts

# Element children access
puts "Access .element_children (elements only)"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_root.element_children }
  x.report("nokogiri") { nokogiri_root.element_children } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts

# Parent access
puts "Access .parent on deep node"
puts "-" * 80

rxerces_deep = rxerces_doc.xpath('//paragraph').first
nokogiri_deep = nokogiri_doc.xpath('//paragraph').first if NOKOGIRI_AVAILABLE

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_deep.parent }
  x.report("nokogiri") { nokogiri_deep.parent } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts

# Ancestors access
puts "Access .ancestors on deep node"
puts "-" * 80

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_deep.ancestors }
  x.report("nokogiri") { nokogiri_deep.ancestors } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts

# Next sibling
puts "Access .next_sibling"
puts "-" * 80

rxerces_para = rxerces_doc.xpath('//paragraph').first
nokogiri_para = nokogiri_doc.xpath('//paragraph').first if NOKOGIRI_AVAILABLE

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_para.next_sibling }
  x.report("nokogiri") { nokogiri_para.next_sibling } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts

# Text extraction
puts "Extract .text from element"
puts "-" * 80

rxerces_section = rxerces_doc.xpath('//section').first
nokogiri_section = nokogiri_doc.xpath('//section').first if NOKOGIRI_AVAILABLE

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("rxerces") { rxerces_section.text }
  x.report("nokogiri") { nokogiri_section.text } if NOKOGIRI_AVAILABLE

  x.compare!
end

puts
puts "=" * 80
