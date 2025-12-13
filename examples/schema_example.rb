#!/usr/bin/env ruby
require_relative '../lib/rxerces'

# Define an XSD schema
schema_xsd = <<~XSD
  <?xml version="1.0"?>
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

puts "=" * 60
puts "RXerces Schema Validation Example"
puts "=" * 60

# Create a schema from the XSD
puts "\nCreating schema from XSD..."
schema = RXerces::XML::Schema.from_string(schema_xsd)
puts "✓ Schema created successfully"

# Test 1: Valid document
puts "\n" + "-" * 60
puts "Test 1: Validating a VALID document"
puts "-" * 60

valid_xml = <<~XML
  <?xml version="1.0"?>
  <person>
    <name>John Doe</name>
    <age>30</age>
    <email>john@example.com</email>
  </person>
XML

doc = RXerces::XML::Document.parse(valid_xml)
errors = doc.validate(schema)
if errors.empty?
  puts "✓ Document is VALID (no validation errors)"
else
  puts "✗ Document has validation errors:"
  errors.each { |error| puts "  - #{error}" }
end

# Test 2: Invalid document (missing required element)
puts "\n" + "-" * 60
puts "Test 2: Validating an INVALID document (missing 'email')"
puts "-" * 60

invalid_xml = <<~XML
  <?xml version="1.0"?>
  <person>
    <name>Jane Doe</name>
    <age>25</age>
  </person>
XML

doc2 = RXerces::XML::Document.parse(invalid_xml)
errors2 = doc2.validate(schema)
if errors2.empty?
  puts "✓ Document is VALID (no validation errors)"
else
  puts "✗ Document has validation errors (as expected):"
  errors2.each { |error| puts "  - #{error}" }
end

# Test 3: Invalid document (wrong type)
puts "\n" + "-" * 60
puts "Test 3: Validating an INVALID document (wrong type for 'age')"
puts "-" * 60

invalid_xml2 = <<~XML
  <?xml version="1.0"?>
  <person>
    <name>Bob Smith</name>
    <age>not-a-number</age>
    <email>bob@example.com</email>
  </person>
XML

doc3 = RXerces::XML::Document.parse(invalid_xml2)
errors3 = doc3.validate(schema)
if errors3.empty?
  puts "✓ Document is VALID (no validation errors)"
else
  puts "✗ Document has validation errors (as expected):"
  errors3.each { |error| puts "  - #{error}" }
end

# You can also create a schema from a document
puts "\n" + "-" * 60
puts "Creating schema from a Document object..."
puts "-" * 60
schema_doc = RXerces::XML::Document.parse(schema_xsd)
schema2 = RXerces::XML::Schema.from_document(schema_doc)
puts "✓ Schema created from Document"

puts "\n" + "=" * 60
puts "Full XSD validation is now implemented using Xerces-C!"
puts "=" * 60
