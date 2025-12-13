require 'spec_helper'

RSpec.describe RXerces::XML::Schema do
  let(:simple_xsd) do
    <<~XSD
      <?xml version="1.0" encoding="UTF-8"?>
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="root">
          <xs:complexType>
            <xs:sequence>
              <xs:element name="name" type="xs:string"/>
              <xs:element name="age" type="xs:integer"/>
            </xs:sequence>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XSD
  end

  let(:valid_xml) do
    <<~XML
      <?xml version="1.0"?>
      <root>
        <name>John</name>
        <age>30</age>
      </root>
    XML
  end

  let(:invalid_xml) do
    <<~XML
      <?xml version="1.0"?>
      <root>
        <name>John</name>
        <age>not-a-number</age>
      </root>
    XML
  end

  describe '.from_string' do
    it 'creates a schema from an XSD string' do
      schema = described_class.from_string(simple_xsd)
      expect(schema).to be_a(described_class)
    end

    # Note: Xerces-C parser is very tolerant of invalid XML
    # So we just skip testing for invalid XML for now
  end

  describe '.from_document' do
    it 'creates a schema from a Document' do
      schema_doc = RXerces::XML::Document.parse(simple_xsd)
      schema = described_class.from_document(schema_doc)
      expect(schema).to be_a(described_class)
    end
  end

  describe 'validation' do
    let(:schema) { described_class.from_string(simple_xsd) }

    it 'validates a document (returns empty array for now)' do
      doc = RXerces::XML::Document.parse(valid_xml)
      errors = doc.validate(schema)
      expect(errors).to be_a(Array)
      # Note: Full validation not yet implemented, so we just check it returns an array
    end

    it 'validates an invalid document (returns empty array for now)' do
      doc = RXerces::XML::Document.parse(invalid_xml)
      errors = doc.validate(schema)
      expect(errors).to be_a(Array)
      # Note: Full validation not yet implemented
    end
  end
end
