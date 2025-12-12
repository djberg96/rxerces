require 'spec_helper'
require 'rxerces/nokogiri'

RSpec.describe "XPath support" do
  let(:xml) do
    <<-XML
      <library>
        <book id="1" category="fiction">
          <title>1984</title>
          <author>George Orwell</author>
          <year>1949</year>
          <price>15.99</price>
        </book>
        <book id="2" category="fiction">
          <title>Brave New World</title>
          <author>Aldous Huxley</author>
          <year>1932</year>
          <price>14.99</price>
        </book>
        <book id="3" category="non-fiction">
          <title>Sapiens</title>
          <author>Yuval Noah Harari</author>
          <year>2011</year>
          <price>18.99</price>
        </book>
      </library>
    XML
  end

  let(:doc) { RXerces::XML::Document.parse(xml) }

  describe "Document XPath queries" do
    it "finds all book elements" do
      books = doc.xpath('//book')
      expect(books).to be_a(RXerces::XML::NodeSet)
      expect(books.length).to eq(3)
    end

    it "finds all title elements" do
      titles = doc.xpath('//title')
      expect(titles.length).to eq(3)
      expect(titles[0].text.strip).to eq('1984')
      expect(titles[1].text.strip).to eq('Brave New World')
      expect(titles[2].text.strip).to eq('Sapiens')
    end

    it "finds elements by path" do
      authors = doc.xpath('/library/book/author')
      expect(authors.length).to eq(3)
    end

    it "finds descendant elements" do
      years = doc.xpath('//year')
      expect(years.length).to eq(3)
    end

    it "finds price elements" do
      prices = doc.xpath('//price')
      expect(prices.length).to eq(3)
    end

    it "returns empty nodeset for non-matching xpath" do
      result = doc.xpath('//nonexistent')
      expect(result).to be_a(RXerces::XML::NodeSet)
      expect(result.length).to eq(0)
    end

    it "can find nested elements" do
      library_books = doc.xpath('/library/book')
      expect(library_books.length).to eq(3)
    end
  end

  describe "Node XPath queries" do
    let(:root) { doc.root }

    it "finds children from root element" do
      books = root.xpath('.//book')
      expect(books.length).to eq(3)
    end

    it "finds specific child elements" do
      first_book = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      titles = first_book.xpath('.//title')
      expect(titles.length).to eq(1)
      expect(titles[0].text.strip).to eq('1984')
    end

    it "finds descendant elements from node" do
      first_book = root.children.find { |n| n.is_a?(RXerces::XML::Element) }
      author = first_book.xpath('.//author')
      expect(author.length).to eq(1)
      expect(author[0].text.strip).to eq('George Orwell')
    end

    it "can use relative paths" do
      books = root.xpath('book')
      expect(books.length).to eq(3)
    end

    it "finds all descendants" do
      all_titles = root.xpath('.//title')
      expect(all_titles.length).to eq(3)
    end
  end

  describe "Error handling" do
    it "raises error for invalid XPath" do
      expect {
        doc.xpath('//[invalid')
      }.to raise_error(RuntimeError, /XPath error/)
    end
  end

  describe "Nokogiri compatibility" do
    it "works with Nokogiri syntax" do
      nokogiri_doc = Nokogiri::XML(xml)
      books = nokogiri_doc.xpath('//book')
      expect(books).to be_a(Nokogiri::XML::NodeSet)
      expect(books.length).to eq(3)
    end

    it "can chain xpath on results" do
      books = doc.xpath('//book')
      expect(books.length).to eq(3)

      # Access first book's title
      first_book = books[0]
      titles = first_book.xpath('.//title')
      expect(titles.length).to eq(1)
      expect(titles[0].text.strip).to eq('1984')
    end

    it "can iterate over xpath results" do
      authors = doc.xpath('//author')
      author_names = []
      authors.each do |author|
        author_names << author.text.strip
      end
      expect(author_names).to include('George Orwell', 'Aldous Huxley', 'Yuval Noah Harari')
    end
  end

  describe "XPath limitations" do
    it "notes that Xerces-C uses XML Schema XPath subset" do
      # Xerces-C implements the XML Schema XPath subset, not full XPath 1.0
      # This means the following are NOT supported:
      # - Attribute predicates like [@id="1"]
      # - Functions like last(), position(), text()
      # - Comparison operators in predicates
      #
      # However, basic path expressions work well:
      # - // (descendant-or-self)
      # - / (child)
      # - . (self)
      # - .. (parent)

      # Basic paths work
      expect(doc.xpath('//book').length).to eq(3)
      expect(doc.xpath('/library/book').length).to eq(3)
      expect(doc.xpath('//title').length).to eq(3)
    end
  end
end
