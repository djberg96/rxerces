#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark/ips'
require 'rxerces'

begin
  require 'nokogiri'
  NOKOGIRI_AVAILABLE = true
rescue LoadError
  NOKOGIRI_AVAILABLE = false
  warn "Nokogiri not available - install with: gem install nokogiri"
end

# Sample XML for microbenchmarks
XML_DATA = begin
  sections = (1..200).map do |i|
    "<section id=\"s#{i}\">\n" \
    "  <article id=\"a#{i}\">\n" \
    "    <header>\n" \
    "      <title>Title #{i}</title>\n" \
    "      <author>Author #{i}</author>\n" \
    "    </header>\n" \
    "    <content>\n" \
    "      <paragraph class=\"p\">Paragraph 1</paragraph>\n" \
    "      <paragraph class=\"p\">Paragraph 2</paragraph>\n" \
    "      <paragraph class=\"p special\">Paragraph 3</paragraph>\n" \
    "    </content>\n" \
    "    <footer>\n" \
    "      <date>2024-01-01</date>\n" \
    "    </footer>\n" \
    "  </article>\n" \
    "</section>"
  end
  "<root>#{sections.join}</root>"
end

puts "=" * 80
puts "Node Method Microbenchmarks"
puts "=" * 80
puts "Document Size: #{XML_DATA.bytesize} bytes"
puts

# Parse once
rx_doc = RXerces::XML::Document.parse(XML_DATA)
ng_doc = Nokogiri::XML(XML_DATA) if NOKOGIRI_AVAILABLE

rx_root = rx_doc.root
ng_root = ng_doc.root if NOKOGIRI_AVAILABLE

rx_para = rx_doc.xpath('//paragraph').first
ng_para = ng_doc.xpath('//paragraph').first if NOKOGIRI_AVAILABLE

rx_section = rx_doc.xpath('//section').first
ng_section = ng_doc.xpath('//section').first if NOKOGIRI_AVAILABLE

# Helper to run a labeled microbenchmark for two blocks
def run_micro(title)
  puts title
  puts '-' * 80
  Benchmark.ips do |x|
    x.config(time: 5, warmup: 2)
    yield x
    x.compare!
  end
  puts
end

# children
run_micro('Node#children (array)') do |x|
  x.report('rxerces') { rx_root.children }
  x.report('nokogiri') { ng_root.children } if NOKOGIRI_AVAILABLE
end

# element_children
run_micro('Node#element_children (elements only)') do |x|
  x.report('rxerces') { rx_root.element_children }
  x.report('nokogiri') { ng_root.element_children } if NOKOGIRI_AVAILABLE
end

# parent
run_micro('Node#parent (deep node)') do |x|
  x.report('rxerces') { rx_para.parent }
  x.report('nokogiri') { ng_para.parent } if NOKOGIRI_AVAILABLE
end

# ancestors
run_micro('Node#ancestors (deep node)') do |x|
  x.report('rxerces') { rx_para.ancestors }
  x.report('nokogiri') { ng_para.ancestors } if NOKOGIRI_AVAILABLE
end

# next_sibling
run_micro('Node#next_sibling') do |x|
  x.report('rxerces') { rx_para.next_sibling }
  x.report('nokogiri') { ng_para.next_sibling } if NOKOGIRI_AVAILABLE
end

# previous_sibling
run_micro('Node#previous_sibling') do |x|
  x.report('rxerces') { rx_para.previous_sibling }
  x.report('nokogiri') { ng_para.previous_sibling } if NOKOGIRI_AVAILABLE
end

# attributes (hash)
run_micro('Node#attributes (hash)') do |x|
  x.report('rxerces') { rx_para.attributes }
  x.report('nokogiri') { ng_para.attributes } if NOKOGIRI_AVAILABLE
end

# [] (attribute get)
run_micro("Node#[] (attribute get 'class')") do |x|
  x.report('rxerces') { rx_para['class'] }
  x.report('nokogiri') { ng_para['class'] } if NOKOGIRI_AVAILABLE
end

# []= (attribute set) — set same value repeatedly to avoid growth
run_micro("Node#[]= (attribute set 'data-x')") do |x|
  x.report('rxerces') { rx_para['data-x'] = '42' }
  x.report('nokogiri') { ng_para['data-x'] = '42' } if NOKOGIRI_AVAILABLE
end

# text
run_micro('Node#text (aggregate)') do |x|
  x.report('rxerces') { rx_section.text }
  x.report('nokogiri') { ng_section.text } if NOKOGIRI_AVAILABLE
end

# inner_html
run_micro('Node#inner_html') do |x|
  x.report('rxerces') { rx_section.inner_html }
  x.report('nokogiri') { ng_section.inner_html } if NOKOGIRI_AVAILABLE
end

# path
run_micro('Node#path') do |x|
  x.report('rxerces') { rx_para.path }
  x.report('nokogiri') { ng_para.path } if NOKOGIRI_AVAILABLE
end

# blank?
run_micro('Node#blank?') do |x|
  x.report('rxerces') { rx_para.blank? }
  x.report('nokogiri') { ng_para.blank? } if NOKOGIRI_AVAILABLE
end

# at_xpath
run_micro("Document#at_xpath('//title')") do |x|
  x.report('rxerces') { rx_doc.at_xpath('//title') }
  x.report('nokogiri') { ng_doc.at_xpath('//title') } if NOKOGIRI_AVAILABLE
end

# xpath (nodeset size)
run_micro("Document#xpath('//paragraph') length") do |x|
  x.report('rxerces') { rx_doc.xpath('//paragraph').length }
  x.report('nokogiri') { ng_doc.xpath('//paragraph').length } if NOKOGIRI_AVAILABLE
end

# css
run_micro("Document#css('.special') length") do |x|
  x.report('rxerces') { rx_doc.css('.special').length }
  x.report('nokogiri') { ng_doc.css('.special').length } if NOKOGIRI_AVAILABLE
end

# serialization
run_micro('Document#to_s (serialize)') do |x|
  x.report('rxerces') { rx_doc.to_s }
  x.report('nokogiri') { ng_doc.to_s } if NOKOGIRI_AVAILABLE
end

puts '=' * 80
puts 'Microbenchmarks complete.'
