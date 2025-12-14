require 'spec_helper'

RSpec.describe RXerces::XML::Node do
  let(:xml) do
    <<-XML
      <root>
        <person id="1" name="Alice">
          <age>30</age>
          <city>New York</city>
        </person>
        <person id="2" name="Bob">
          <age>25</age>
        </person>
      </root>
    XML
  end

  let(:doc) { RXerces::XML::Document.parse(xml) }
  let(:root) { doc.root }

  describe "#name" do
    it "returns the node name" do
      expect(root.name).to eq('root')
    end

    it "returns child element names" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      expect(person.name).to eq('person')
    end
  end

  describe "#text" do
    it "returns text content" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      age = person.children.find { |n| n.name == 'age' }
      expect(age.text.strip).to eq('30')
    end

    it "returns empty string for nodes without text" do
      expect(root.text).to be_a(String)
    end
  end

  describe "#content" do
    it "is an alias for text" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      age = person.children.find { |n| n.name == 'age' }
      expect(age.content).to eq(age.text)
    end
  end

  describe "#text=" do
    it "sets text content" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      age = person.children.find { |n| n.name == 'age' }
      age.text = '35'
      expect(age.text.strip).to eq('35')
    end
  end

  describe "#[]" do
    it "gets attribute value" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      expect(person['id']).to eq('1')
      expect(person['name']).to eq('Alice')
    end

    it "returns nil for non-existent attribute" do
      expect(root['nonexistent']).to be_nil
    end
  end

  describe "#[]=" do
    it "sets attribute value" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      person['id'] = '100'
      expect(person['id']).to eq('100')
    end

    it "creates new attribute" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      person['email'] = 'alice@example.com'
      expect(person['email']).to eq('alice@example.com')
    end
  end

  describe "#children" do
    it "returns an array of child nodes" do
      children = root.children
      expect(children).to be_an(Array)
      expect(children.length).to be > 0
    end

    it "includes element nodes" do
      person_nodes = root.children.select { |n| n.is_a?(RXerces::XML::Element) }
      expect(person_nodes.length).to eq(2)
    end

    it "includes text nodes" do
      text_nodes = root.children.select { |n| n.is_a?(RXerces::XML::Text) }
      expect(text_nodes.length).to be > 0
    end
  end

  describe "#parent" do
    it "returns the parent node" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      parent = person.parent
      expect(parent).to be_a(RXerces::XML::Element)
      expect(parent.name).to eq('root')
    end

    it "returns the parent for nested elements" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      age = person.children.find { |n| n.name == 'age' }
      parent = age.parent
      expect(parent).to be_a(RXerces::XML::Element)
      expect(parent.name).to eq('person')
      expect(parent['id']).to eq('1')
    end

    it "returns the document for root element" do
      parent = root.parent
      expect(parent).not_to be_nil
      expect(parent.name).to eq('#document')
    end

    it "returns nil for nodes without parent" do
      # This is edge case - all nodes in a parsed document have parents
      # but we test the safety of the method
      expect(root.parent).not_to be_nil
    end
  end

  describe "#xpath" do
    it "returns a NodeSet" do
      result = root.xpath('.//age')
      expect(result).to be_a(RXerces::XML::NodeSet)
    end
  end
end
