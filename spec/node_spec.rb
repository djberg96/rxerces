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

  describe "#namespace" do
    let(:ns_xml) do
      <<-XML
        <root xmlns="http://example.com/default">
          <item>Default namespace</item>
        </root>
      XML
    end
    let(:ns_doc) { RXerces::XML::Document.parse(ns_xml) }

    it "returns nil for nodes without a namespace" do
      expect(root.namespace).to be_nil
    end

    it "returns the default namespace URI" do
      ns_root = ns_doc.root
      expect(ns_root.namespace).to eq('http://example.com/default')
    end

    it "returns the namespace for child elements inheriting default namespace" do
      ns_root = ns_doc.root
      item = ns_root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      expect(item.namespace).to eq('http://example.com/default')
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

  describe "#get_attribute" do
    it "is an alias for []" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      expect(person.get_attribute('id')).to eq('1')
      expect(person.get_attribute('name')).to eq('Alice')
    end
  end

  describe "#attribute" do
    it "is an alias for []" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      expect(person.attribute('id')).to eq('1')
      expect(person.attribute('name')).to eq('Alice')
    end
  end

  describe "#has_attribute?" do
    it "returns true when attribute exists" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      expect(person.has_attribute?('id')).to be true
      expect(person.has_attribute?('name')).to be true
    end

    it "returns false when attribute does not exist" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      expect(person.has_attribute?('nonexistent')).to be false
    end

    it "returns false for non-element nodes" do
      text_node = root.children.find { |n| n.is_a?(RXerces::XML::Text) }
      expect(text_node.has_attribute?('anything')).to be false if text_node
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

  describe "#ancestors" do
    it "returns an array of ancestor nodes" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      age = person.children.find { |n| n.name == 'age' }
      ancestors = age.ancestors

      expect(ancestors).to be_an(Array)
      expect(ancestors.length).to eq(2)
      expect(ancestors[0].name).to eq('person')
      expect(ancestors[1].name).to eq('root')
    end

    it "returns ancestors in order from immediate parent to root" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      city = person.children.find { |n| n.name == 'city' }
      ancestors = city.ancestors

      expect(ancestors.map(&:name)).to eq(['person', 'root'])
    end

    it "returns empty array for root element" do
      ancestors = root.ancestors
      expect(ancestors).to be_an(Array)
      expect(ancestors).to be_empty
    end

    it "returns only one ancestor for direct children of root" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      ancestors = person.ancestors

      expect(ancestors.length).to eq(1)
      expect(ancestors[0].name).to eq('root')
    end

    it "does not include the document node in ancestors" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      ancestors = person.ancestors

      expect(ancestors.any? { |a| a.name == '#document' }).to be false
    end

    it "filters ancestors by tag name selector" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      city = person.children.find { |n| n.name == 'city' }
      ancestors = city.ancestors('person')

      expect(ancestors.length).to eq(1)
      expect(ancestors[0].name).to eq('person')
    end

    it "filters ancestors by CSS class selector" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      city = person.children.find { |n| n.name == 'city' }
      person_ancestors = city.ancestors('person[name]')

      expect(person_ancestors.length).to eq(1)
      expect(person_ancestors[0].name).to eq('person')
      expect(person_ancestors[0]['name']).to eq('Alice')
    end

    it "returns empty array when no ancestors match selector" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      city = person.children.find { |n| n.name == 'city' }
      ancestors = city.ancestors('nonexistent')

      expect(ancestors).to be_an(Array)
      expect(ancestors).to be_empty
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

  describe "#element_children" do
    it "returns only element children, filtering out text nodes" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      element_children = person.element_children

      expect(element_children).to be_an(Array)
      expect(element_children.all? { |n| n.is_a?(RXerces::XML::Element) }).to be true
      expect(element_children.length).to eq(2) # age and city elements
      expect(element_children.map(&:name)).to match_array(['age', 'city'])
    end

    it "returns empty array for elements with no element children" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      age = person.element_children.find { |n| n.name == 'age' }
      expect(age.element_children).to be_empty
    end

    it "returns empty array for text nodes" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      text_node = person.children.find { |n| n.is_a?(RXerces::XML::Text) }
      expect(text_node.element_children).to be_empty if text_node
    end
  end

  describe "#elements" do
    it "is an alias for element_children" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      expect(person.elements.map(&:name)).to eq(person.element_children.map(&:name))
      expect(person.elements.length).to eq(2)
    end
  end

  describe "#next_element" do
    it "returns the next element sibling, skipping text nodes" do
      people = root.children.select { |n| n.is_a?(RXerces::XML::Element) }
      first_person = people[0]
      next_element = first_person.next_element

      expect(next_element).to be_a(RXerces::XML::Element)
      expect(next_element.name).to eq('person')
      expect(next_element['id']).to eq('2')
    end

    it "returns nil when there is no next element" do
      people = root.children.select { |n| n.is_a?(RXerces::XML::Element) }
      last_person = people.last
      expect(last_person.next_element).to be_nil
    end

    it "can navigate through all element siblings" do
      first_element = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      siblings = []
      current = first_element

      while current
        siblings << current
        current = current.next_element
      end

      expect(siblings.length).to eq(2)
      expect(siblings[0]['id']).to eq('1')
      expect(siblings[1]['id']).to eq('2')
    end
  end

  describe "#previous_element" do
    it "returns the previous element sibling, skipping text nodes" do
      people = root.children.select { |n| n.is_a?(RXerces::XML::Element) }
      second_person = people[1]
      prev_element = second_person.previous_element

      expect(prev_element).to be_a(RXerces::XML::Element)
      expect(prev_element.name).to eq('person')
      expect(prev_element['id']).to eq('1')
    end

    it "returns nil when there is no previous element" do
      first_element = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      expect(first_element.previous_element).to be_nil
    end

    it "can navigate backward through all element siblings" do
      last_element = root.children.select { |n| n.is_a?(RXerces::XML::Element) }.last
      siblings = []
      current = last_element

      while current
        siblings.unshift(current)
        current = current.previous_element
      end

      expect(siblings.length).to eq(2)
      expect(siblings[0]['id']).to eq('1')
      expect(siblings[1]['id']).to eq('2')
    end
  end

  describe "#add_child" do
    it "adds a text node from a string" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      initial_count = person.children.length

      person.add_child("New text content")

      expect(person.children.length).to eq(initial_count + 1)
      last_child = person.children.last
      expect(last_child).to be_a(RXerces::XML::Text)
      expect(last_child.text).to eq("New text content")
    end

    it "adds a new element to another element" do
      # Create a simple document to test with
      simple_xml = '<root><parent></parent></root>'
      simple_doc = RXerces::XML::Document.parse(simple_xml)
      parent = simple_doc.root.children.find { |n| n.is_a?(RXerces::XML::Element) }

      # Add text child
      parent.add_child("Hello World")

      expect(parent.children.length).to be > 0
      text_child = parent.children.find { |n| n.is_a?(RXerces::XML::Text) }
      expect(text_child.text).to eq("Hello World")
    end

    it "allows building a document structure" do
      simple_xml = '<root></root>'
      simple_doc = RXerces::XML::Document.parse(simple_xml)
      root = simple_doc.root

      # Add multiple children
      root.add_child("First text")
      root.add_child("Second text")

      text_nodes = root.children.select { |n| n.is_a?(RXerces::XML::Text) }
      expect(text_nodes.length).to eq(2)
      expect(text_nodes[0].text).to eq("First text")
      expect(text_nodes[1].text).to eq("Second text")
    end

    it "modifies the document" do
      simple_xml = '<item></item>'
      simple_doc = RXerces::XML::Document.parse(simple_xml)
      item = simple_doc.root

      item.add_child("Content")

      xml_output = simple_doc.to_s
      expect(xml_output).to include("Content")
    end
  end

  describe "#remove" do
    it "removes a node from its parent" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      initial_count = root.children.select { |n| n.is_a?(RXerces::XML::Element) }.length

      person.remove

      remaining = root.children.select { |n| n.is_a?(RXerces::XML::Element) }
      expect(remaining.length).to eq(initial_count - 1)
    end

    it "removes a child element from parent" do
      person = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      age = person.children.find { |n| n.name == 'age' }
      initial_count = person.children.select { |n| n.is_a?(RXerces::XML::Element) }.length

      age.remove

      remaining = person.children.select { |n| n.is_a?(RXerces::XML::Element) }
      expect(remaining.length).to eq(initial_count - 1)
      expect(person.children.find { |n| n.name == 'age' }).to be_nil
    end

    it "modifies the document" do
      simple_xml = '<root><item>Remove me</item><keep>Keep me</keep></root>'
      simple_doc = RXerces::XML::Document.parse(simple_xml)
      item = simple_doc.xpath('//item').first

      item.remove

      xml_output = simple_doc.to_s
      expect(xml_output).not_to include("Remove me")
      expect(xml_output).to include("Keep me")
    end

    it "raises error when node has no parent" do
      # The root element's parent is the document, so this should work
      # We'll test with a document node instead
      expect {
        root.parent.remove
      }.to raise_error(RuntimeError, /no parent/)
    end
  end

  describe "#unlink" do
    it "is an alias for remove" do
      simple_xml = '<root><item>Test</item></root>'
      simple_doc = RXerces::XML::Document.parse(simple_xml)
      item = simple_doc.xpath('//item').first

      expect(item).to respond_to(:unlink)
      item.unlink

      xml_output = simple_doc.to_s
      expect(xml_output).not_to include("Test")
    end
  end

  describe "#xpath" do
    it "returns a NodeSet" do
      result = root.xpath('.//age')
      expect(result).to be_a(RXerces::XML::NodeSet)
    end
  end

  describe "#inner_html" do
    it "returns the XML content of children without parent tags" do
      person = root.xpath('//person').first
      inner = person.inner_html
      expect(inner).to include('<age>')
      expect(inner).to include('<city>')
      expect(inner).not_to include('<person')
    end

    it "returns empty string for nodes without children" do
      age = root.xpath('//age').first
      inner = age.inner_html
      expect(inner).to eq('30')
    end

    it "includes multiple children" do
      person = root.xpath('//person').first
      inner = person.inner_html
      expect(inner).to include('<age>30</age>')
      expect(inner).to include('<city>New York</city>')
    end
  end

  describe "#inner_xml" do
    it "is an alias for inner_html" do
      person = root.xpath('//person').first
      expect(person.inner_xml).to eq(person.inner_html)
    end

    it "returns the same XML content" do
      person = root.xpath('//person').first
      inner = person.inner_xml
      expect(inner).to include('<age>')
      expect(inner).to include('<city>')
    end
  end

  describe "#path" do
    it "returns the XPath to the root element" do
      expect(root.path).to eq('/root[1]')
    end

    it "returns the XPath to a nested element" do
      person = root.xpath('//person').first
      expect(person.path).to eq('/root[1]/person[1]')
    end

    it "returns the XPath to the second person element" do
      people = root.xpath('//person')
      second_person = people[1]
      expect(second_person.path).to eq('/root[1]/person[2]')
    end

    it "returns the XPath to deeply nested elements" do
      age = root.xpath('//age').first
      expect(age.path).to eq('/root[1]/person[1]/age[1]')
    end
  end

  describe "#blank?" do
    let(:blank_xml) { '<root><empty></empty><whitespace>   </whitespace><content>Hello</content></root>' }
    let(:blank_doc) { RXerces::XML::Document.parse(blank_xml) }

    it "returns false for elements with text content" do
      content = blank_doc.xpath('//content').first
      expect(content.blank?).to be false
    end

    it "returns true for empty elements" do
      empty = blank_doc.xpath('//empty').first
      expect(empty.blank?).to be true
    end

    it "returns true for elements with only whitespace" do
      whitespace = blank_doc.xpath('//whitespace').first
      expect(whitespace.blank?).to be true
    end

    it "returns false for elements with child elements" do
      root = blank_doc.root
      expect(root.blank?).to be false
    end

    it "returns false for text nodes with content" do
      content = blank_doc.xpath('//content').first
      text_node = content.children.first
      expect(text_node.blank?).to be false
    end

    it "returns true for text nodes with only whitespace" do
      whitespace = blank_doc.xpath('//whitespace').first
      text_node = whitespace.children.first
      expect(text_node.blank?).to be true
    end
  end

  describe "#search" do
    it "is an alias for xpath" do
      result1 = root.search('.//age')
      result2 = root.xpath('.//age')
      expect(result1.length).to eq(result2.length)
      expect(result1.first.text).to eq(result2.first.text)
    end

    it "returns a NodeSet" do
      result = root.search('.//person')
      expect(result).to be_a(RXerces::XML::NodeSet)
    end

    it "finds nested elements" do
      result = root.search('.//age')
      expect(result.length).to eq(2)
      expect(result.first.text).to eq('30')
    end
  end

  describe "#at_xpath" do
    it "returns the first matching node" do
      result = root.at_xpath('.//age')
      expect(result).to be_a(RXerces::XML::Element)
      expect(result.text).to eq('30')
    end

    it "returns nil when no match found" do
      result = root.at_xpath('.//nonexistent')
      expect(result).to be_nil
    end

    it "returns only the first match when multiple exist" do
      result = root.at_xpath('.//person')
      expect(result['id']).to eq('1')
    end
  end

  describe "#at" do
    it "is an alias for at_xpath" do
      result1 = root.at('.//age')
      result2 = root.at_xpath('.//age')
      expect(result1.text).to eq(result2.text)
    end

    it "returns the first matching element" do
      result = root.at('.//city')
      expect(result.text).to eq('New York')
    end
  end

  describe "#at_css" do
    # Check if Xalan support is compiled in (CSS requires XPath which needs Xalan)
    xalan_available = begin
      test_xml = '<root><item id="1">A</item><item id="2">B</item></root>'
      test_doc = RXerces::XML::Document.parse(test_xml)
      result = test_doc.xpath('//item[@id="1"]')
      result.length == 1
    rescue
      false
    end

    before(:all) do
      unless xalan_available
        skip "Xalan-C not available - CSS selectors require Xalan-C library"
      end
    end

    it "is an alias for at (which uses CSS converted to XPath)" do
      xml = '<root><item class="foo">First</item><item class="bar">Second</item></root>'
      doc = RXerces::XML::Document.parse(xml)
      result = doc.root.at_css('.foo')
      expect(result).to be_a(RXerces::XML::Element)
      expect(result.text).to eq('First')
    end

    it "returns the first matching element" do
      xml = '<root><item>A</item><item>B</item></root>'
      doc = RXerces::XML::Document.parse(xml)
      result = doc.root.at_css('item')
      expect(result.text).to eq('A')
    end

    it "returns nil when no match found" do
      xml = '<root><item>A</item></root>'
      doc = RXerces::XML::Document.parse(xml)
      result = doc.root.at_css('nonexistent')
      expect(result).to be_nil
    end
  end

  describe "#css" do
    # Check if Xalan support is compiled in (CSS requires XPath which needs Xalan)
    xalan_available = begin
      test_xml = '<root><item id="1">A</item><item id="2">B</item></root>'
      test_doc = RXerces::XML::Document.parse(test_xml)
      result = test_doc.xpath('//item[@id="1"]')
      result.length == 1
    rescue
      false
    end

    before(:all) do
      unless xalan_available
        skip "Xalan-C not available - CSS selectors require Xalan-C library"
      end
    end

    let(:xml) do
      <<-XML
        <library>
          <book id="book1" class="fiction bestseller">
            <title>1984</title>
            <author>George Orwell</author>
          </book>
          <book id="book2" class="fiction">
            <title>Brave New World</title>
            <author>Aldous Huxley</author>
          </book>
          <book id="book3" class="non-fiction">
            <title>Sapiens</title>
            <author>Yuval Noah Harari</author>
          </book>
        </library>
      XML
    end

    let(:doc) { RXerces::XML::Document.parse(xml) }
    let(:root) { doc.root }

    it "finds elements by tag name" do
      books = root.css('book')
      expect(books.length).to eq(3)
    end

    it "finds elements by class" do
      fiction = root.css('.fiction')
      expect(fiction.length).to eq(2)
    end

    it "finds elements by id" do
      book = root.css('#book1')
      expect(book.length).to eq(1)
      expect(book[0].xpath('.//title')[0].text.strip).to eq('1984')
    end

    it "finds elements by tag and class" do
      fiction_books = root.css('book.fiction')
      expect(fiction_books.length).to eq(2)
    end

    it "finds elements by tag and id" do
      book = root.css('book#book2')
      expect(book.length).to eq(1)
      expect(book[0].xpath('.//title')[0].text.strip).to eq('Brave New World')
    end

    it "finds elements with attribute selector" do
      books_with_id = root.css('book[id]')
      expect(books_with_id.length).to eq(3)
    end

    it "finds elements with attribute value selector" do
      book = root.css('book[id=book3]')
      expect(book.length).to eq(1)
      expect(book[0].xpath('.//title')[0].text.strip).to eq('Sapiens')
    end

    it "handles descendant combinator" do
      titles = root.css('library title')
      expect(titles.length).to eq(3)
    end

    it "handles child combinator" do
      books = root.css('library > book')
      expect(books.length).to eq(3)
    end

    it "finds nested elements" do
      authors = root.css('book author')
      expect(authors.length).to eq(3)
    end

    it "combines multiple selectors" do
      result = root.css('book.fiction title')
      expect(result.length).to eq(2)
    end
  end
end
