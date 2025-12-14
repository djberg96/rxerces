require 'spec_helper'

RSpec.describe RXerces::XML::Document do
  let(:simple_xml) { '<root><child>Hello</child></root>' }
  let(:complex_xml) do
    <<-XML
      <root>
        <person id="1" name="Alice">
          <age>30</age>
          <city>New York</city>
        </person>
        <person id="2" name="Bob">
          <age>25</age>
          <city>London</city>
        </person>
      </root>
    XML
  end

  describe ".parse" do
    it "parses simple XML" do
      doc = RXerces::XML::Document.parse(simple_xml)
      expect(doc).to be_a(RXerces::XML::Document)
    end

    it "parses complex XML" do
      doc = RXerces::XML::Document.parse(complex_xml)
      expect(doc).to be_a(RXerces::XML::Document)
    end
  end

  describe "#root" do
    it "returns the root element" do
      doc = RXerces::XML::Document.parse(simple_xml)
      root = doc.root
      expect(root).to be_a(RXerces::XML::Element)
      expect(root.name).to eq('root')
    end
  end

  describe "#to_s" do
    it "serializes document to string" do
      doc = RXerces::XML::Document.parse(simple_xml)
      xml_string = doc.to_s
      expect(xml_string).to be_a(String)
      expect(xml_string).to include('<root>')
      expect(xml_string).to include('<child>')
      expect(xml_string).to include('Hello')
    end
  end

  describe "#to_xml" do
    it "is an alias for to_s" do
      doc = RXerces::XML::Document.parse(simple_xml)
      expect(doc.to_xml).to eq(doc.to_s)
    end
  end

  describe "#xpath" do
    it "returns a NodeSet" do
      doc = RXerces::XML::Document.parse(simple_xml)
      result = doc.xpath('//child')
      expect(result).to be_a(RXerces::XML::NodeSet)
    end
  end

  describe "#create_element" do
    let(:doc) { RXerces::XML::Document.parse(simple_xml) }

    it "creates a new element with the specified name" do
      element = doc.create_element('book')
      expect(element).to be_a(RXerces::XML::Element)
      expect(element.name).to eq('book')
    end

    it "creates an element that can have attributes set" do
      element = doc.create_element('book')
      attributes = element.attributes
      expect(attributes).to be_a(Hash)
      expect(attributes).to be_empty
    end

    it "creates an element that can have children added" do
      element = doc.create_element('book')
      element.add_child('Test Content')
      expect(element.text).to eq('Test Content')
    end

    it "creates an element that can be added to the document" do
      root = doc.root
      new_element = doc.create_element('new_child')
      new_element.add_child('New content')
      root.add_child(new_element)

      # Verify the new element is in the document
      result = doc.xpath('//new_child')
      expect(result.length).to eq(1)
      expect(result.first.text).to eq('New content')
    end
  end
end
