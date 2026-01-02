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

    it "handles empty documents" do
      expect {
        RXerces::XML::Document.parse('')
      }.to raise_error(RuntimeError, /invalid document structure/)
    end

    it "handles documents with only XML declaration" do
      expect {
        RXerces::XML::Document.parse('<?xml version="1.0"?>')
      }.to raise_error(RuntimeError, /invalid document structure/)
    end

    it "handles deeply nested elements" do
      # Create XML with 50 levels of nesting
      xml = '<root>'
      50.times { |i| xml += "<level#{i}>" }
      xml += 'deep content'
      50.times { |i| xml += "</level#{49-i}>" }
      xml += '</root>'

      doc = RXerces::XML::Document.parse(xml)
      expect(doc).to be_a(RXerces::XML::Document)
      expect(doc.root.name).to eq('root')

      # Verify we can access deeply nested content
      deepest = doc.root
      50.times { |i| deepest = deepest.element_children.first }
      expect(deepest.text).to eq('deep content')
    end

    it "handles documents with CDATA sections" do
      xml_with_cdata = '<root><![CDATA[<not>&parsed;]]></root>'
      doc = RXerces::XML::Document.parse(xml_with_cdata)
      expect(doc.root.text).to eq('<not>&parsed;')
    end

    it "handles documents with processing instructions" do
      xml_with_pi = '<?xml-stylesheet type="text/xsl" href="style.xsl"?><root>content</root>'
      doc = RXerces::XML::Document.parse(xml_with_pi)
      expect(doc.root.text).to eq('content')
    end

    it "handles documents with comments" do
      xml_with_comment = '<root><!-- This is a comment -->content</root>'
      doc = RXerces::XML::Document.parse(xml_with_comment)
      expect(doc.root.text).to eq('content')
    end

    it "handles mixed content" do
      mixed_xml = '<root>text <b>bold</b> more text <i>italic</i> end</root>'
      doc = RXerces::XML::Document.parse(mixed_xml)
      expect(doc.root.children.length).to eq(5) # 3 text nodes + 2 elements
      expect(doc.root.text).to eq('text bold more text italic end')
    end

    it "handles elements with many attributes" do
      xml_many_attrs = '<root ' + (1..100).map { |i| "attr#{i}=\"value#{i}\"" }.join(' ') + '>content</root>'
      doc = RXerces::XML::Document.parse(xml_many_attrs)
      expect(doc.root.attributes.length).to eq(100)
      expect(doc.root['attr50']).to eq('value50')
    end

    it "handles large text content" do
      large_text = 'x' * 10000
      xml_large = "<root>#{large_text}</root>"
      doc = RXerces::XML::Document.parse(xml_large)
      expect(doc.root.text.length).to eq(10000)
      expect(doc.root.text).to start_with('xxxxx')
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

  describe "#css", xalan: true do
    let(:xml) do
      <<-XML
        <library>
          <book id="book1" class="fiction">
            <title>1984</title>
          </book>
          <book id="book2" class="non-fiction">
            <title>Sapiens</title>
          </book>
        </library>
      XML
    end

    let(:doc) { RXerces::XML::Document.parse(xml) }

    it "returns a NodeSet" do
      result = doc.css('book')
      expect(result).to be_a(RXerces::XML::NodeSet)
    end

    it "finds elements by tag name" do
      books = doc.css('book')
      expect(books.length).to eq(2)
    end

    it "finds elements by class" do
      fiction = doc.css('.fiction')
      expect(fiction.length).to eq(1)
    end

    it "finds elements by id" do
      book = doc.css('#book1')
      expect(book.length).to eq(1)
      expect(book[0].xpath('.//title')[0].text.strip).to eq('1984')
    end

    it "finds elements with combined selectors" do
      fiction_books = doc.css('book.fiction')
      expect(fiction_books.length).to eq(1)
    end
  end

  describe "#encoding" do
    it "returns UTF-8 for documents without explicit encoding" do
      doc = RXerces::XML::Document.parse(simple_xml)
      expect(doc.encoding).to eq('UTF-8')
    end

    it "returns the encoding specified in the XML declaration" do
      xml_with_encoding = '<?xml version="1.0" encoding="ISO-8859-1"?><root><item>Test</item></root>'
      doc = RXerces::XML::Document.parse(xml_with_encoding)
      expect(doc.encoding).to eq('ISO-8859-1')
    end

    it "returns the encoding for UTF-16 documents" do
      xml_with_encoding = '<?xml version="1.0" encoding="UTF-16"?><root><item>Test</item></root>'
      doc = RXerces::XML::Document.parse(xml_with_encoding)
      expect(doc.encoding).to eq('UTF-16')
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

  describe "#errors" do
    it "returns empty array for valid XML" do
      doc = RXerces::XML::Document.parse(simple_xml)
      expect(doc.errors).to eq([])
    end

    it "returns empty array for complex valid XML" do
      doc = RXerces::XML::Document.parse(complex_xml)
      expect(doc.errors).to eq([])
    end

    context "with malformed XML" do
      it "raises error and provides line/column information for unclosed tags" do
        expect {
          RXerces::XML::Document.parse('<root><item>test</root>')
        }.to raise_error(RuntimeError, /Fatal error at line \d+, column \d+/)
      end

      it "raises error with detailed message for multiple errors" do
        expect {
          RXerces::XML::Document.parse('<root><item>test</item><unclosed>')
        }.to raise_error(RuntimeError, /Fatal error at line/)
      end

      it "raises error for completely invalid XML" do
        expect {
          RXerces::XML::Document.parse('not xml at all')
        }.to raise_error(RuntimeError, /Fatal error at line/)
      end

      it "raises error for mismatched tags" do
        expect {
          RXerces::XML::Document.parse('<root><item>test</other></root>')
        }.to raise_error(RuntimeError, /Fatal error at line/)
      end
    end

    context "error message format" do
      it "includes line number in error message" do
        expect {
          RXerces::XML::Document.parse('<root><bad>')
        }.to raise_error(RuntimeError, /line \d+/)
      end

      it "includes column number in error message" do
        expect {
          RXerces::XML::Document.parse('<root><bad>')
        }.to raise_error(RuntimeError, /column \d+/)
      end

      it "describes the error type" do
        expect {
          RXerces::XML::Document.parse('<root><item>test</root>')
        }.to raise_error(RuntimeError, /expected end of tag/)
      end
    end
  end

  describe "parse options validation" do
    let(:simple_xml) { '<root><child>test</child></root>' }

    context "with valid options" do
      it "accepts no options" do
        expect {
          RXerces::XML::Document.parse(simple_xml)
        }.not_to raise_error
      end

      it "accepts nil options" do
        expect {
          RXerces::XML::Document.parse(simple_xml, nil)
        }.not_to raise_error
      end

      it "accepts empty hash" do
        expect {
          RXerces::XML::Document.parse(simple_xml, {})
        }.not_to raise_error
      end

      it "accepts allow_external_entities with symbol key" do
        expect {
          doc = RXerces::XML::Document.parse(simple_xml, allow_external_entities: false)
          expect(doc).to be_a(RXerces::XML::Document)
        }.not_to raise_error
      end

      it "accepts allow_external_entities with string key" do
        expect {
          doc = RXerces::XML::Document.parse(simple_xml, 'allow_external_entities' => false)
          expect(doc).to be_a(RXerces::XML::Document)
        }.not_to raise_error
      end

      it "accepts allow_external_entities set to true" do
        expect {
          doc = RXerces::XML::Document.parse(simple_xml, allow_external_entities: true)
          expect(doc).to be_a(RXerces::XML::Document)
        }.not_to raise_error
      end
    end

    context "with invalid options" do
      it "rejects unknown option keys" do
        expect {
          RXerces::XML::Document.parse(simple_xml, unknown_option: true)
        }.to raise_error(ArgumentError, /Unknown option: unknown_option/)
      end

      it "rejects multiple unknown options and reports the first one" do
        expect {
          RXerces::XML::Document.parse(simple_xml, foo: 1, bar: 2)
        }.to raise_error(ArgumentError, /Unknown option:/)
      end

      it "lists allowed options in error message" do
        expect {
          RXerces::XML::Document.parse(simple_xml, invalid: true)
        }.to raise_error(ArgumentError, /Allowed options are: allow_external_entities/)
      end

      it "rejects options with both valid and invalid keys" do
        expect {
          RXerces::XML::Document.parse(simple_xml,
                                      allow_external_entities: true,
                                      invalid_key: false)
        }.to raise_error(ArgumentError, /Unknown option: invalid_key/)
      end

      it "rejects non-string, non-symbol keys" do
        expect {
          RXerces::XML::Document.parse(simple_xml, 123 => true)
        }.to raise_error(ArgumentError, /Option keys must be symbols or strings/)
      end

      it "rejects options that are not a hash" do
        expect {
          RXerces::XML::Document.parse(simple_xml, "not a hash")
        }.to raise_error(TypeError)
      end

      it "rejects options array" do
        expect {
          RXerces::XML::Document.parse(simple_xml, [:allow_external_entities])
        }.to raise_error(TypeError)
      end
    end

    context "security" do
      it "prevents typos from silently disabling security features" do
        # If someone mistypes allow_external_entities, it should fail
        # rather than silently ignoring the option
        expect {
          RXerces::XML::Document.parse(simple_xml, allow_external_entity: true)
        }.to raise_error(ArgumentError, /Unknown option/)
      end

      it "prevents typos with underscores" do
        expect {
          RXerces::XML::Document.parse(simple_xml, allowexternalentities: true)
        }.to raise_error(ArgumentError, /Unknown option/)
      end

      it "prevents similar-looking options" do
        expect {
          RXerces::XML::Document.parse(simple_xml, external_entities: true)
        }.to raise_error(ArgumentError, /Unknown option/)
      end
    end
  end
end
