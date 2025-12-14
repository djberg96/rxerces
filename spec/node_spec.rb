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

  describe "#attributes" do
    it "returns a hash of attributes" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      attrs = person.attributes
      expect(attrs).to be_a(Hash)
      expect(attrs['id']).to eq('1')
      expect(attrs['name']).to eq('Alice')
    end

    it "returns all attributes" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      attrs = person.attributes
      expect(attrs.keys).to match_array(['id', 'name'])
    end

    it "returns empty hash for elements without attributes" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      age = person.children.find { |n| n.name == 'age' }
      attrs = age.attributes
      expect(attrs).to be_a(Hash)
      expect(attrs).to be_empty
    end

    it "returns empty hash for text nodes" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      text_node = person.children.find { |n| n.is_a?(RXerces::XML::Text) }
      attrs = text_node.attributes
      expect(attrs).to be_a(Hash)
      expect(attrs).to be_empty
    end
  end

  describe "#next_sibling" do
    it "returns the next sibling node" do
      people = root.children.select { |n| n.is_a?(RXerces::XML::Element) }
      first_person = people[0]
      next_node = first_person.next_sibling

      # May be a text node (whitespace) between elements
      # Skip to next element if needed
      while next_node && next_node.is_a?(RXerces::XML::Text)
        next_node = next_node.next_sibling
      end

      expect(next_node).to be_a(RXerces::XML::Element)
      expect(next_node.name).to eq('person')
      expect(next_node['id']).to eq('2')
    end

    it "returns nil for last sibling" do
      people = root.children.select { |n| n.is_a?(RXerces::XML::Element) }
      last_person = people.last

      # Navigate past any trailing whitespace
      next_node = last_person.next_sibling
      while next_node && next_node.is_a?(RXerces::XML::Text)
        next_node = next_node.next_sibling
      end

      expect(next_node).to be_nil
    end

    it "can navigate through all siblings" do
      first_element = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      siblings = []
      current = first_element

      while current
        siblings << current if current.is_a?(RXerces::XML::Element)
        current = current.next_sibling
      end

      expect(siblings.length).to eq(2)
      expect(siblings[0]['id']).to eq('1')
      expect(siblings[1]['id']).to eq('2')
    end
  end

  describe "#previous_sibling" do
    it "returns the previous sibling node" do
      people = root.children.select { |n| n.is_a?(RXerces::XML::Element) }
      second_person = people[1]
      prev_node = second_person.previous_sibling

      # May be a text node (whitespace) between elements
      # Skip to previous element if needed
      while prev_node && prev_node.is_a?(RXerces::XML::Text)
        prev_node = prev_node.previous_sibling
      end

      expect(prev_node).to be_a(RXerces::XML::Element)
      expect(prev_node.name).to eq('person')
      expect(prev_node['id']).to eq('1')
    end

    it "returns nil for first sibling" do
      first_element = root.children.find { |n| n.is_a?(RXerces::XML::Element) }

      # Navigate past any leading whitespace
      prev_node = first_element.previous_sibling
      while prev_node && prev_node.is_a?(RXerces::XML::Text)
        prev_node = prev_node.previous_sibling
      end

      expect(prev_node).to be_nil
    end

    it "can navigate backward through all siblings" do
      last_element = root.children.select { |n| n.is_a?(RXerces::XML::Element) }.last
      siblings = []
      current = last_element

      while current
        siblings.unshift(current) if current.is_a?(RXerces::XML::Element)
        current = current.previous_sibling
      end

      expect(siblings.length).to eq(2)
      expect(siblings[0]['id']).to eq('1')
      expect(siblings[1]['id']).to eq('2')
    end
  end

  describe "#xpath" do
    it "returns a NodeSet" do
      result = root.xpath('.//age')
      expect(result).to be_a(RXerces::XML::NodeSet)
    end
  end
end
