require 'spec_helper'

RSpec.describe 'Native binding operations' do
  it 'preserves child order and node types while walking siblings' do
    doc = RXerces.XML('<root>text<!--before--><first/><![CDATA[data]]><last/><!--after--> </root>')
    root = doc.root

    expect(root.children.map(&:name)).to eq(
      ['#text', '#comment', 'first', '#cdata-section', 'last', '#comment', '#text']
    )
    expect(root.element_children.map(&:name)).to eq(['first', 'last'])
    expect(root.first_element_child.name).to eq('first')
    expect(root.last_element_child.name).to eq('last')
  end

  it 'skips document comments and processing instructions for element access' do
    doc = RXerces.XML('<!--before--><?test value?><root/><!--after-->')

    expect(doc.children.map(&:name)).to eq(['#comment', 'test', 'root', '#comment'])
    expect(doc.element_children.map(&:name)).to eq(['root'])
    expect(doc.first_element_child.name).to eq('root')
    expect(doc.last_element_child.name).to eq('root')
  end

  it 'returns nil for element endpoints when there are no element children' do
    ['<root/>', '<root>text<!--comment--><![CDATA[data]]></root>'].each do |xml|
      root = RXerces.XML(xml).root
      expect(root.first_element_child).to be_nil
      expect(root.last_element_child).to be_nil
      expect(root.element_children).to be_empty
    end
  end

  it 'reflects mutations in child traversal' do
    root = RXerces.XML('<root><first/><last/></root>').root
    root.first_element_child.remove
    expect(root.first_element_child.name).to eq('last')
    root.last_element_child.remove
    expect(root.children).to be_empty
    expect(root.first_element_child).to be_nil
    expect(root.last_element_child).to be_nil
  end

  it 'returns the first XPath match in document order and respects node context' do
    doc = RXerces.XML('<root><group><item id="1"/><item id="2"/></group><group><item id="3"/></group></root>')

    expect(doc.at_xpath('//item')['id']).to eq('1')
    expect(doc.root.last_element_child.at_xpath('.//item')['id']).to eq('3')
    expect(doc.at_css('item')['id']).to eq('1')
    expect(doc.root.at_css('item')['id']).to eq('1')
    expect(doc.at_xpath('//missing')).to be_nil
    expect(doc.root.at_xpath('.//missing')).to be_nil
    expect(doc.at_css('missing')).to be_nil
    expect(doc.root.at_css('missing')).to be_nil
  end

  it 'validates first-match XPath expressions' do
    doc = RXerces.XML('<root/>')
    [doc, doc.root].each do |context|
      expect { context.at_xpath('') }.to raise_error(ArgumentError)
      expect { context.at_xpath('document("file.xml")') }.to raise_error(ArgumentError)
      expect { context.at_xpath('[') }.to raise_error(ArgumentError)
    end
  end

  it 'keeps the document alive through first-match results' do
    node = RXerces.XML('<root><item id="1"/></root>').at_xpath('//item')
    GC.start
    expect(node['id']).to eq('1')
    expect(node.document.root.name).to eq('root')
  end

  it 'serializes UTF-8 with a matching declaration and round-trips Unicode' do
    text = 'café 日本語 😀 & < >'
    doc = RXerces.XML('<root>café 日本語 😀 &amp; &lt; &gt;</root>')
    serialized = doc.to_xml

    expect(serialized.encoding).to eq(Encoding::UTF_8)
    expect(serialized).to be_valid_encoding
    expect(serialized).to include('encoding="UTF-8"')
    expect(RXerces.XML(serialized).root.text.b).to eq(text.b)
  end

  it 'serializes non-UTF-8 input as correctly declared UTF-8' do
    doc = RXerces.XML('<?xml version="1.0" encoding="ISO-8859-1"?><root>caf&#233;</root>')
    serialized = doc.to_xml

    expect(serialized).to include('encoding="UTF-8"', 'café')
    expect(RXerces.XML(serialized).root.text.b).to eq('café'.b)
  end
end
