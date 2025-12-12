[![Ruby](https://github.com/djberg96/rxerces/actions/workflows/ci.yml/badge.svg)](https://github.com/djberg96/rxerces/actions/workflows/ci.yml)

# RXerces

A Ruby XML library with a Nokogiri-compatible API, powered by Apache Xerces-C instead of libxml2.

## Overview

RXerces provides a familiar Nokogiri-like interface for XML parsing and manipulation, but uses the robust Apache Xerces-C XML parser under the hood. This allows Ruby developers to leverage Xerces-C's performance and standards compliance while maintaining compatibility with existing Nokogiri-based code.

## Features

- ✅ Nokogiri-compatible API
- ✅ Powered by Apache Xerces-C
- ✅ Parse XML documents
- ✅ Navigate and manipulate DOM trees
- ✅ Read and write node attributes
- ✅ Query nodes with XPath (basic support)
- ✅ Serialize documents back to XML strings

## Installation

### Prerequisites

You need to have Xerces-C installed on your system:

**macOS (Homebrew):**
```bash
brew install xerces-c
```

**Ubuntu/Debian:**
```bash
sudo apt-get install libxerces-c-dev
```

**Fedora/RHEL:**
```bash
sudo yum install xerces-c-devel
```

### Install the Gem

Add this line to your application's Gemfile:

```ruby
gem 'rxerces'
```

And then execute:
```bash
bundle install
```

Or install it yourself as:
```bash
gem install rxerces
```

## Usage

### Basic Parsing

```ruby
require 'rxerces'

# Parse XML string
xml = '<root><person name="Alice">Hello</person></root>'
doc = RXerces.XML(xml)

# Access root element
root = doc.root
puts root.name  # => "root"
```

### Nokogiri Compatibility

RXerces provides a `Nokogiri` module for drop-in compatibility:

```ruby
require 'rxerces'

# Use Nokogiri syntax
doc = Nokogiri.XML('<root><child>text</child></root>')
puts doc.root.name  # => "root"

# Classes are aliased
Nokogiri::XML::Document == RXerces::XML::Document  # => true
```

### Working with Nodes

```ruby
# Parse XML
xml = <<-XML
  <library>
    <book id="1" title="1984">
      <author>George Orwell</author>
      <year>1949</year>
    </book>
    <book id="2" title="Brave New World">
      <author>Aldous Huxley</author>
      <year>1932</year>
    </book>
  </library>
XML

doc = RXerces.XML(xml)
root = doc.root

# Get attributes
book = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
puts book['id']     # => "1"
puts book['title']  # => "1984"

# Set attributes
book['isbn'] = '978-0451524935'
puts book['isbn']   # => "978-0451524935"

# Get text content
author = book.children.find { |n| n.name == 'author' }
puts author.text    # => "George Orwell"

# Set text content
author.text = "Eric Arthur Blair"
puts author.text    # => "Eric Arthur Blair"
```

### Navigating the DOM

```ruby
# Get all children
root.children.each do |child|
  puts "#{child.name}: #{child.class}"
end

# Find specific elements
books = root.children.select { |n| n.is_a?(RXerces::XML::Element) && n.name == 'book' }
books.each do |book|
  puts "Book ID: #{book['id']}"
end
```

### Serialization

```ruby
# Convert document back to XML string
xml_string = doc.to_xml
puts xml_string

# or use to_s
puts doc.to_s
```

### XPath Queries

RXerces supports XPath queries using Xerces-C's XPath implementation:

```ruby
xml = <<-XML
  <library>
    <book>
      <title>1984</title>
      <author>George Orwell</author>
    </book>
    <book>
      <title>Brave New World</title>
      <author>Aldous Huxley</author>
    </book>
  </library>
XML

doc = RXerces.XML(xml)

# Find all book elements
books = doc.xpath('//book')
puts books.length  # => 2

# Find all titles
titles = doc.xpath('//title')
titles.each do |title|
  puts title.text.strip
end

# Use path expressions
authors = doc.xpath('/library/book/author')
puts authors.length  # => 2

# Query from a specific node
first_book = books[0]
title = first_book.xpath('.//title').first
puts title.text  # => "1984"
```

**Note on XPath Support**: Xerces-C implements the XML Schema XPath subset, not full XPath 1.0. Supported features include:
- Basic path expressions (`/`, `//`, `.`, `..`)
- Element selection by name
- Descendant and child axes

Not supported:
- Attribute predicates (`[@attribute="value"]`)
- XPath functions (`last()`, `position()`, `text()`)
- Comparison operators in predicates

For more complex queries, you can combine basic XPath with Ruby's `select` and `find` methods.

## API Reference

### RXerces Module

- `RXerces.XML(string)` - Parse XML string and return Document
- `RXerces.parse(string)` - Alias for `XML`

### RXerces::XML::Document

- `.parse(string)` - Parse XML string (class method)
- `#root` - Get root element
- `#to_s` / `#to_xml` - Serialize to XML string
- `#xpath(path)` - Query with XPath (returns NodeSet)

### RXerces::XML::Node

- `#name` - Get node name
- `#text` / `#content` - Get text content
- `#text=` / `#content=` - Set text content
- `#[attribute]` - Get attribute value
- `#[attribute]=` - Set attribute value
- `#children` - Get array of child nodes
- `#xpath(path)` - Query descendants with XPath

### RXerces::XML::Element

Inherits all methods from `Node`. Represents element nodes.

### RXerces::XML::Text

Inherits all methods from `Node`. Represents text nodes.

### RXerces::XML::NodeSet

- `#length` / `#size` - Get number of nodes
- `#[]` - Access node by index
- `#each` - Iterate over nodes (Enumerable)
- `#to_a` - Convert to array

## Development

### Building the Extension

```bash
bundle install
bundle exec rake compile
```

### Running Tests

```bash
bundle exec rspec
```

### Running Tests with Compilation

```bash
bundle exec rake
```

## Implementation Notes

- Uses Apache Xerces-C 3.x for XML parsing
- C++ extension compiled with Ruby's native extension API
- XPath support is basic (full XPath requires additional implementation)
- Memory management handled by Ruby's GC and Xerces-C's DOM

## Differences from Nokogiri

While RXerces aims for API compatibility with Nokogiri, there are some differences:

1. **Parser Backend**: Uses Xerces-C instead of libxml2
2. **XPath**: Basic XPath support (returns empty NodeSet currently)
3. **Features**: Subset of Nokogiri's full feature set
4. **Performance**: Different performance characteristics due to Xerces-C

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## License

MIT License - see LICENSE file for details

## Credits

- Built with [Apache Xerces-C](https://xerces.apache.org/xerces-c/)
- API inspired by [Nokogiri](https://nokogiri.org/)

## Misc
This library was almost entirely written using AI (Claude Sonnet 4.5). It
was mainly a reaction to the lack of maintainers for libxml2, and the generally
sorry state of that library in general. Since nokogiri uses it under the hood,
I thought it best to create an alternative.

## Copyright
(C) 2025, Daniel J. Berger
All Rights Reserved

## Author
* Daniel J. Berger
