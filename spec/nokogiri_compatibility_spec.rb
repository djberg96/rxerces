require 'spec_helper'
require 'rxerces/nokogiri'

RSpec.describe "Nokogiri compatibility" do
  let(:simple_xml) { '<root><child>Hello</child></root>' }

  describe "Nokogiri module" do
    it "exists" do
      expect(defined?(Nokogiri)).to eq('constant')
    end

    describe ".XML" do
      it "parses XML" do
        doc = Nokogiri.XML(simple_xml)
        expect(doc).to be_a(RXerces::XML::Document)
      end
    end

    describe ".parse" do
      it "is an alias for .XML" do
        doc = Nokogiri.parse(simple_xml)
        expect(doc).to be_a(RXerces::XML::Document)
      end
    end
  end

  describe "Nokogiri::XML" do
    it "exists" do
      expect(defined?(Nokogiri::XML)).to eq('constant')
    end

    describe ".parse" do
      it "parses XML" do
        doc = Nokogiri::XML.parse(simple_xml)
        expect(doc).to be_a(RXerces::XML::Document)
      end
    end
  end

  describe "Nokogiri::HTML" do
    it "exists" do
      expect(defined?(Nokogiri::HTML)).to eq('constant')
    end

    describe ".parse" do
      it "parses HTML" do
        html = '<html><body><h1>Hello</h1></body></html>'
        doc = Nokogiri::HTML.parse(html)
        expect(doc).to be_a(RXerces::XML::Document)
      end
    end
  end

  describe "Nokogiri.HTML" do
    it "parses HTML" do
      html = '<html><body><h1>Hello</h1></body></html>'
      doc = Nokogiri.HTML(html)
      expect(doc).to be_a(RXerces::XML::Document)
    end
  end

  describe "Nokogiri::HTML class aliases" do
    it "aliases Document" do
      expect(Nokogiri::HTML::Document).to eq(RXerces::XML::Document)
    end

    it "aliases Node" do
      expect(Nokogiri::HTML::Node).to eq(RXerces::XML::Node)
    end

    it "aliases Element" do
      expect(Nokogiri::HTML::Element).to eq(RXerces::XML::Element)
    end

    it "aliases Text" do
      expect(Nokogiri::HTML::Text).to eq(RXerces::XML::Text)
    end

    it "aliases NodeSet" do
      expect(Nokogiri::HTML::NodeSet).to eq(RXerces::XML::NodeSet)
    end
  end

  describe "Nokogiri::XML::Document" do
    it "is an alias for RXerces::XML::Document" do
      expect(Nokogiri::XML::Document).to eq(RXerces::XML::Document)
    end
  end

  describe "Nokogiri::XML::Node" do
    it "is an alias for RXerces::XML::Node" do
      expect(Nokogiri::XML::Node).to eq(RXerces::XML::Node)
    end
  end

  describe "Nokogiri::XML::Element" do
    it "is an alias for RXerces::XML::Element" do
      expect(Nokogiri::XML::Element).to eq(RXerces::XML::Element)
    end
  end

  describe "Nokogiri::XML::NodeSet" do
    it "is an alias for RXerces::XML::NodeSet" do
      expect(Nokogiri::XML::NodeSet).to eq(RXerces::XML::NodeSet)
    end
  end

  describe "Nokogiri::XML::Schema" do
    it "is an alias for RXerces::XML::Schema" do
      expect(Nokogiri::XML::Schema).to eq(RXerces::XML::Schema)
    end
  end

  describe "API compatibility" do
    let(:doc) { Nokogiri.XML(simple_xml) }

    it "provides root method" do
      expect(doc.root).to be_a(Nokogiri::XML::Element)
      expect(doc.root.name).to eq('root')
    end

    it "provides to_s method" do
      xml_string = doc.to_s
      expect(xml_string).to be_a(String)
      expect(xml_string).to include('<root>')
    end

    it "provides to_xml method" do
      xml_string = doc.to_xml
      expect(xml_string).to be_a(String)
      expect(xml_string).to include('<root>')
    end

    it "provides node name method" do
      expect(doc.root.name).to eq('root')
    end

    it "provides node text method" do
      child = doc.root.children.find { |n| n.is_a?(Nokogiri::XML::Element) }
      expect(child.text).to be_a(String)
    end

    it "provides node children method" do
      children = doc.root.children
      expect(children).to be_an(Array)
    end
  end

  describe "Schema validation compatibility" do
    let(:xsd) do
      <<~XSD
        <?xml version="1.0"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="person">
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
        <person>
          <name>John</name>
          <age>30</age>
        </person>
      XML
    end

    let(:invalid_xml) do
      <<~XML
        <?xml version="1.0"?>
        <person>
          <name>Jane</name>
          <age>invalid</age>
        </person>
      XML
    end

    it "provides Schema.from_string method" do
      schema = Nokogiri::XML::Schema.from_string(xsd)
      expect(schema).to be_a(Nokogiri::XML::Schema)
    end

    it "provides Schema.from_document method" do
      doc = Nokogiri::XML.parse(xsd)
      schema = Nokogiri::XML::Schema.from_document(doc)
      expect(schema).to be_a(Nokogiri::XML::Schema)
    end

    it "validates a valid document" do
      schema = Nokogiri::XML::Schema.from_string(xsd)
      doc = Nokogiri::XML.parse(valid_xml)
      errors = doc.validate(schema)
      expect(errors).to be_empty
    end

    it "returns errors for an invalid document" do
      schema = Nokogiri::XML::Schema.from_string(xsd)
      doc = Nokogiri::XML.parse(invalid_xml)
      errors = doc.validate(schema)
      expect(errors).not_to be_empty
    end
  end
end
