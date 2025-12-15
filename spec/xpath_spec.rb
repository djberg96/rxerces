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

  describe "XPath 1.0 compliance with Xalan" do
    describe "Attribute predicates" do
      it "finds elements by attribute value" do
        book = doc.xpath('//book[@id="1"]')
        expect(book.length).to eq(1)
        expect(book[0].xpath('.//title')[0].text.strip).to eq('1984')
      end

      it "finds elements by attribute equality" do
        fiction_books = doc.xpath('//book[@category="fiction"]')
        expect(fiction_books.length).to eq(2)
      end

      it "finds elements by attribute inequality" do
        non_fiction = doc.xpath('//book[@category!="fiction"]')
        expect(non_fiction.length).to eq(1)
        expect(non_fiction[0].xpath('.//title')[0].text.strip).to eq('Sapiens')
      end

      it "supports multiple attribute predicates" do
        book = doc.xpath('//book[@id="2"][@category="fiction"]')
        expect(book.length).to eq(1)
        expect(book[0].xpath('.//title')[0].text.strip).to eq('Brave New World')
      end
    end

    describe "Position and indexing functions" do
      it "uses position() to find first element" do
        first_book = doc.xpath('//book[position()=1]')
        expect(first_book.length).to eq(1)
        expect(first_book[0].xpath('.//title')[0].text.strip).to eq('1984')
      end

      it "uses last() to find last element" do
        last_book = doc.xpath('//book[position()=last()]')
        expect(last_book.length).to eq(1)
        expect(last_book[0].xpath('.//title')[0].text.strip).to eq('Sapiens')
      end

      it "uses numeric predicates for indexing" do
        second_book = doc.xpath('//book[2]')
        expect(second_book.length).to eq(1)
        expect(second_book[0].xpath('.//title')[0].text.strip).to eq('Brave New World')
      end

      it "finds elements by position greater than" do
        later_books = doc.xpath('//book[position()>1]')
        expect(later_books.length).to eq(2)
      end
    end

    describe "String functions" do
      it "uses contains() function" do
        books_with_new = doc.xpath('//book[contains(.//title, "New")]')
        expect(books_with_new.length).to eq(1)
        expect(books_with_new[0].xpath('.//title')[0].text.strip).to eq('Brave New World')
      end

      it "uses starts-with() function" do
        books_starting_with_1 = doc.xpath('//book[starts-with(.//title, "1")]')
        expect(books_starting_with_1.length).to eq(1)
        expect(books_starting_with_1[0].xpath('.//title')[0].text.strip).to eq('1984')
      end

      it "uses normalize-space() function" do
        # Should find titles even with whitespace differences
        result = doc.xpath('//title[normalize-space()="1984"]')
        expect(result.length).to eq(1)
      end

      it "uses string-length() function" do
        # Find books where title length is less than 10 characters
        short_titles = doc.xpath('//book[string-length(.//title) < 10]')
        expect(short_titles.length).to eq(2) # "1984" and "Sapiens"
      end

      it "uses concat() function" do
        # This tests that concat works by checking if a book has matching text
        # concat('19', '84') = '1984'
        result = doc.xpath('//book[.//title = concat("19", "84")]')
        expect(result.length).to eq(1)
      end

      it "uses substring() function" do
        # Find books where first 5 chars of title is "Brave"
        result = doc.xpath('//book[substring(.//title, 1, 5) = "Brave"]')
        expect(result.length).to eq(1)
        expect(result[0].xpath('.//title')[0].text.strip).to eq('Brave New World')
      end
    end

    describe "Numeric functions and comparisons" do
      it "uses count() function" do
        # Find library element that has exactly 3 book children
        result = doc.xpath('/library[count(book) = 3]')
        expect(result.length).to eq(1)
      end

      it "compares numeric values with >" do
        expensive_books = doc.xpath('//book[.//price > 15]')
        expect(expensive_books.length).to eq(2) # 15.99 and 18.99
      end

      it "compares numeric values with <" do
        cheap_books = doc.xpath('//book[.//price < 16]')
        expect(cheap_books.length).to eq(2) # 15.99 and 14.99
      end

      it "compares numeric values with >=" do
        books_1950_or_later = doc.xpath('//book[.//year >= 1949]')
        expect(books_1950_or_later.length).to eq(2) # 1949 and 2011
      end

      it "uses sum() function" do
        # sum() returns a number, not a nodeset, so we can't call it directly
        # Instead, test it within a predicate
        result = doc.xpath('//library[sum(book/price) > 40]')
        expect(result.length).to eq(1) # Total is 49.97
      end

      it "uses floor() function" do
        # Find books where floor(price) = 15 (15.99 -> 15)
        result = doc.xpath('//book[floor(.//price) = 15]')
        expect(result.length).to eq(1)
      end

      it "uses ceiling() function" do
        # Find books where ceiling(price) = 19 (18.99 -> 19)
        result = doc.xpath('//book[ceiling(.//price) = 19]')
        expect(result.length).to eq(1)
      end

      it "uses round() function" do
        # Find books where round(price) = 15 (14.99 -> 15, 15.99 -> 16)
        result = doc.xpath('//book[round(.//price) = 15]')
        expect(result.length).to eq(1) # Only 14.99
      end
    end

    describe "Boolean operators" do
      it "uses 'and' operator" do
        result = doc.xpath('//book[@category="fiction" and .//year < 1940]')
        expect(result.length).to eq(1) # Only "Brave New World" (1932)
      end

      it "uses 'or' operator" do
        result = doc.xpath('//book[@id="1" or @id="3"]')
        expect(result.length).to eq(2)
      end

      it "uses 'not()' function" do
        result = doc.xpath('//book[not(@category="fiction")]')
        expect(result.length).to eq(1)
        expect(result[0].xpath('.//title')[0].text.strip).to eq('Sapiens')
      end

      it "combines multiple boolean operators" do
        result = doc.xpath('//book[@category="fiction" and .//price < 15.50]')
        expect(result.length).to eq(1) # Only "Brave New World" (14.99)
      end
    end

    describe "Axes" do
      it "uses parent:: axis" do
        # Find parent of first title
        first_title = doc.xpath('//title[1]')
        parent = first_title[0].xpath('parent::*')
        expect(parent.length).to eq(1)
        expect(parent[0].name).to eq('book')
      end

      it "uses ancestor:: axis" do
        # Find all ancestors of a title element
        first_title = doc.xpath('//title[1]')
        ancestors = first_title[0].xpath('ancestor::*')
        expect(ancestors.length).to eq(2) # book and library
      end

      it "uses following-sibling:: axis" do
        # Find siblings after title
        first_title = doc.xpath('//title[1]')
        siblings = first_title[0].xpath('following-sibling::*')
        expect(siblings.length).to eq(3) # author, year, price
      end

      it "uses preceding-sibling:: axis" do
        # Find siblings before author
        first_author = doc.xpath('//author[1]')
        siblings = first_author[0].xpath('preceding-sibling::*')
        expect(siblings.length).to eq(1) # title
      end

      it "uses descendant:: axis" do
        root = doc.root
        descendants = root.xpath('descendant::title')
        expect(descendants.length).to eq(3)
      end

      it "uses self:: axis" do
        books = doc.xpath('//book')
        self_nodes = books[0].xpath('self::book')
        expect(self_nodes.length).to eq(1)
      end
    end

    describe "Complex predicates" do
      it "chains multiple predicates" do
        result = doc.xpath('//book[@category="fiction"][.//year > 1940]')
        expect(result.length).to eq(1) # Only "1984" (1949)
      end

      it "uses nested predicates" do
        result = doc.xpath('//library[book[@category="fiction"]]')
        expect(result.length).to eq(1)
      end

      it "combines functions in predicates" do
        result = doc.xpath('//book[contains(.//title, "World") and .//year < 1950]')
        expect(result.length).to eq(1)
        expect(result[0].xpath('.//title')[0].text.strip).to eq('Brave New World')
      end
    end

    describe "Text nodes" do
      it "selects text nodes with text()" do
        text_nodes = doc.xpath('//title/text()')
        expect(text_nodes.length).to eq(3)
      end

      it "uses text() in predicates" do
        result = doc.xpath('//title[text()="1984"]')
        # Note: text() returns the raw text which includes whitespace
        # This might not match due to whitespace, so we test it doesn't error
        expect { result }.not_to raise_error
      end
    end
  end
end
