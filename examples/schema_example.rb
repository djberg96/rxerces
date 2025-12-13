#!/usr/bin/env ruby
require_relative '../lib/rxerces'

# Define an XSD schema
schema_xsd = <<~XSD
  <?xml version="1.0" encoding="UTF-8"?>
  <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
    <xs:element name="person">
      <xs:complexType>
        <xs:sequence>
          <xs:element name="name" type="xs:string"/>
          <xs:element name="age" type="xs:integer"/>
          <xs:element name="email" type="xs:string"/>
        </xs:sequence>
      </xs:complexType>
    </xs:element>
  </xs:schema>
XSD

# Create a schema from the XSD
puts "Creating schema from XSD..."
schema = RXerces::XML::Schema.from_string(schema_xsd)
puts "✓ Schema created successfully"

# Parse a valid XML document
valid_xml = <<~XML
  <?xml version="1.0"?>
  <person>
    <name>John Doe</name>
    <age>30</age>
    <email>john@example.com</email>
  </person>
XML

puts "\nParsing XML document..."
doc = RXerces::XML::Document.parse(valid_xml)
puts "✓ Document parsed successfully"

# Validate the document against the schema
puts "\nValidating document against schema..."
errors = doc.validate(schema)
if errors.empty?
  puts "✓ Document is valid (no validation errors)"
else
  puts "✗ Document has validation errors:"
  errors.each { |error| puts "  - #{error}" }
end

# You can also create a schema from a document
puts "\nCreating schema from a Document object..."
schema_doc = RXerces::XML::Document.parse(schema_xsd)
schema2 = RXerces::XML::Schema.from_document(schema_doc)
puts "✓ Schema created from Document"

puts "\nNote: Full XSD validation is not yet implemented in this version."
puts "The schema API is in place and returns an empty array for now."
puts "Future versions will include full validation support using Xerces-C."
