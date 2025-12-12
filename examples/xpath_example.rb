#!/usr/bin/env ruby
require 'bundler/setup'
require 'rxerces'

puts "=== RXerces XPath Example ===\n\n"

xml = <<-XML
  <bookstore>
    <book category="fiction">
      <title>1984</title>
      <author>George Orwell</author>
      <year>1949</year>
      <price>15.99</price>
    </book>
    <book category="fiction">
      <title>Brave New World</title>
      <author>Aldous Huxley</author>
      <year>1932</year>
      <price>14.99</price>
    </book>
    <book category="non-fiction">
      <title>Sapiens</title>
      <author>Yuval Noah Harari</author>
      <year>2011</year>
      <price>18.99</price>
    </book>
  </bookstore>
XML

doc = RXerces.XML(xml)

puts "1. Finding all books:"
books = doc.xpath('//book')
puts "   Found #{books.length} books"
puts

puts "2. Finding all titles:"
titles = doc.xpath('//title')
titles.each do |title|
  puts "   - #{title.text.strip}"
end
puts

puts "3. Finding all authors:"
authors = doc.xpath('//author')
authors.each do |author|
  puts "   - #{author.text.strip}"
end
puts

puts "4. Using absolute paths:"
bookstore_books = doc.xpath('/bookstore/book')
puts "   Found #{bookstore_books.length} books via absolute path"
puts

puts "5. Querying from a specific node:"
first_book = books[0]
title = first_book.xpath('.//title').first
author = first_book.xpath('.//author').first
puts "   First book: #{title.text.strip} by #{author.text.strip}"
puts

puts "6. Combining XPath with Ruby methods:"
puts "   All books with their details:"
books.each_with_index do |book, i|
  title_node = book.xpath('.//title').first
  author_node = book.xpath('.//author').first
  year_node = book.xpath('.//year').first
  price_node = book.xpath('.//price').first

  puts "   Book #{i + 1}:"
  puts "     Title:  #{title_node.text.strip}"
  puts "     Author: #{author_node.text.strip}"
  puts "     Year:   #{year_node.text.strip}"
  puts "     Price:  $#{price_node.text.strip}"
  puts "     Category: #{book['category']}"
  puts
end

puts "7. Filtering with Ruby:"
puts "   Fiction books only:"
fiction_books = books.select { |book| book['category'] == 'fiction' }
fiction_books.each do |book|
  title = book.xpath('.//title').first
  puts "   - #{title.text.strip}"
end
puts

puts "8. Finding nested elements:"
all_prices = doc.xpath('//book/price')
puts "   Found #{all_prices.length} prices:"
total = 0
all_prices.each do |price|
  amount = price.text.strip.to_f
  total += amount
  puts "   - $#{amount}"
end
puts "   Total: $#{'%.2f' % total}"
puts

puts "9. Nokogiri compatibility:"
nokogiri_doc = Nokogiri.XML(xml)
nokogiri_books = nokogiri_doc.xpath('//book')
puts "   Parsed with Nokogiri: #{nokogiri_books.length} books found"
puts

puts "=== Example Complete ==="
puts "\nNote: Xerces-C supports the XML Schema XPath subset."
puts "For advanced filtering, combine basic XPath with Ruby methods."
