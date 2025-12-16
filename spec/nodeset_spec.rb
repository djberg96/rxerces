require 'spec_helper'

RSpec.describe RXerces::XML::NodeSet do
  let(:xml) do
    <<-XML
      <root>
        <item>First</item>
        <item>Second</item>
        <item>Third</item>
      </root>
    XML
  end

  let(:doc) { RXerces::XML::Document.parse(xml) }
  let(:nodeset) { doc.xpath('//item') }
  let(:empty_nodeset) { doc.xpath('//nonexistent') }

  describe "#length" do
    it "returns the number of nodes" do
      expect(nodeset.length).to be_a(Integer)
      expect(nodeset.length).to eq(3)
    end

    it "returns 0 for empty nodeset" do
      expect(empty_nodeset.length).to eq(0)
    end
  end

  describe "#size" do
    it "is an alias for length" do
      expect(nodeset.size).to eq(nodeset.length)
    end
  end

  describe "#[]" do
    it "returns node at index" do
      item = nodeset[0]
      expect(item).to be_a(RXerces::XML::Element)
      expect(item.text.strip).to eq('First')
    end

    it "returns nil for out of bounds index" do
      expect(nodeset[999]).to be_nil
    end

    it "returns nil for empty nodeset" do
      expect(empty_nodeset[0]).to be_nil
    end
  end

  describe "#each" do
    it "is enumerable" do
      expect(nodeset).to respond_to(:each)
    end

    it "returns enumerator when no block given" do
      expect(nodeset.each).to be_a(Enumerator)
    end

    it "yields all items in nodeset" do
      count = 0
      nodeset.each { count += 1 }
      expect(count).to eq(3)
    end

    it "yields nothing for empty nodeset" do
      count = 0
      empty_nodeset.each { count += 1 }
      expect(count).to eq(0)
    end

    it "can iterate and access node properties" do
      texts = []
      nodeset.each do |item|
        texts << item.text.strip
      end
      expect(texts).to eq(['First', 'Second', 'Third'])
    end
  end

  describe "#to_a" do
    it "converts to array" do
      result = nodeset.to_a
      expect(result).to be_an(Array)
      expect(result.length).to eq(3)
    end
  end

  describe "#first" do
    it "returns the first node" do
      first = nodeset.first
      expect(first).to be_a(RXerces::XML::Element)
      expect(first.text.strip).to eq('First')
    end

    it "returns nil for empty nodeset" do
      expect(empty_nodeset.first).to be_nil
    end
  end

  describe "#last" do
    it "returns the last node" do
      last = nodeset.last
      expect(last).to be_a(RXerces::XML::Element)
      expect(last.text.strip).to eq('Third')
    end

    it "returns nil for empty nodeset" do
      expect(empty_nodeset.last).to be_nil
    end
  end

  describe "#empty?" do
    it "returns false for non-empty nodeset" do
      expect(nodeset.empty?).to be false
    end

    it "returns true for empty nodeset" do
      expect(empty_nodeset.empty?).to be true
    end
  end

  describe "#inner_html" do
    it "returns concatenated inner_html of all nodes" do
      result = nodeset.inner_html
      expect(result).to be_a(String)
      expect(result).to eq('FirstSecondThird')
    end

    it "returns empty string for empty nodeset" do
      expect(empty_nodeset.inner_html).to eq('')
    end

    it "includes child elements in inner_html" do
      xml_with_children = <<-XML
        <root>
          <div><span>A</span></div>
          <div><span>B</span></div>
        </root>
      XML
      doc = RXerces::XML::Document.parse(xml_with_children)
      divs = doc.xpath('//div')
      expect(divs.inner_html).to include('<span>A</span>')
      expect(divs.inner_html).to include('<span>B</span>')
    end
  end

  it "includes Enumerable" do
    expect(RXerces::XML::NodeSet.ancestors).to include(Enumerable)
  end
end
