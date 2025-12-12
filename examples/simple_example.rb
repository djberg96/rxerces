#!/usr/bin/env ruby
require 'bundler/setup'
require 'rxerces'

puts "=== RXerces Simple Example (No Nokogiri) ===\n\n"

xml = <<-XML
  <bookstore>
    <book>
      <title>1984</title>
      <author>George Orwell</author>
    </book>
  </bookstore>
XML

# Parse using RXerces directly
doc = RXerces.XML(xml)

puts "Document parsed successfully!"
puts "Root element: #{doc.root.name}"
puts

# Find the book
book = doc.root.children.find { |n| n.is_a?(RXerces::XML::Element) }
title = book.children.find { |n| n.name == 'title' }
author = book.children.find { |n| n.name == 'author' }

puts "Book found:"
puts "  Title: #{title.text.strip}"
puts "  Author: #{author.text.strip}"
puts

puts "=== Example Complete ===\n"
puts "Note: This example uses RXerces directly without Nokogiri compatibility."
