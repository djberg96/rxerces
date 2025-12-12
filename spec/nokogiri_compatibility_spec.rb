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
end
