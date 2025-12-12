require 'rxerces'

puts "=== RXerces Basic Usage Example ===\n\n"

# Parse XML
xml = <<-XML
  <library name="City Library">
    <book id="1" isbn="978-0451524935">
      <title>1984</title>
      <author>George Orwell</author>
      <year>1949</year>
    </book>
    <book id="2" isbn="978-0060850524">
      <title>Brave New World</title>
      <author>Aldous Huxley</author>
      <year>1932</year>
    </book>
  </library>
XML

puts "1. Parsing XML document..."
doc = RXerces.XML(xml)
puts "   ✓ Document parsed successfully\n\n"

# Access root element
puts "2. Accessing root element..."
root = doc.root
puts "   Root element name: #{root.name}"
puts "   Library name: #{root['name']}\n\n"

# Navigate children
puts "3. Navigating child elements..."
books = root.children.select { |n| n.is_a?(RXerces::XML::Element) }
puts "   Found #{books.length} books:\n\n"

books.each do |book|
  title = book.children.find { |n| n.name == 'title' }
  author = book.children.find { |n| n.name == 'author' }
  year = book.children.find { |n| n.name == 'year' }

  puts "   Book ##{book['id']}:"
  puts "     Title:  #{title.text.strip}"
  puts "     Author: #{author.text.strip}"
  puts "     Year:   #{year.text.strip}"
  puts "     ISBN:   #{book['isbn']}"
  puts
end

# Modify document
puts "4. Modifying the document..."
first_book = books.first
first_book['rating'] = '5 stars'
title = first_book.children.find { |n| n.name == 'title' }
puts "   Added rating to first book: #{first_book['rating']}"
puts "   First book title: #{title.text.strip}\n\n"

# Serialize back to XML
puts "5. Serializing to XML..."
xml_output = doc.to_xml
puts "   ✓ Document serialized successfully"
puts "\n   Output preview:"
puts "   " + xml_output.lines.first(3).join("   ")
puts "   ...\n\n"

# Nokogiri compatibility
puts "6. Testing Nokogiri compatibility..."
nokogiri_doc = Nokogiri.XML('<test><item>Hello World</item></test>')
puts "   Parsed with Nokogiri.XML: #{nokogiri_doc.root.name}"
item = nokogiri_doc.root.children.find { |n| n.is_a?(Nokogiri::XML::Element) }
puts "   Item text: #{item.text}"
puts "   Document class: #{nokogiri_doc.class}"
puts "   ✓ Nokogiri compatibility confirmed\n\n"

puts "=== Example Complete ==="
