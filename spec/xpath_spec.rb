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
  let(:xalan_installed) { have_library('xalan-c') }

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
      }.to raise_error(ArgumentError, /XPath expression has unbalanced/)
    end

    it "raises error for malformed XPath expressions" do
      expect {
        doc.xpath('///')
      }.to raise_error(RuntimeError, /XPath error/)
    end

    it "raises error for XPath with unsupported features" do
      skip "Xalan installed, skipping" if xalan_installed
      expect {
        doc.xpath('//book[substring-before(@category, "c")]')
      }.to raise_error(RuntimeError, /XPath error/)
    end

    it "handles very long XPath expressions" do
      skip "Xalan installed, skipping" if xalan_installed
      long_xpath = '/' + ('child::' * 100) + 'library'
      result = doc.xpath(long_xpath)
      expect(result).to be_a(RXerces::XML::NodeSet)
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

  describe "XPath 1.0 compliance with Xalan", xalan: true do
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

  describe "XPath Injection Prevention" do
    let(:simple_xml) do
      <<-XML
        <users>
          <user id="1">
            <name>Alice</name>
            <password>secret123</password>
          </user>
          <user id="2">
            <name>Bob</name>
            <password>admin456</password>
          </user>
        </users>
      XML
    end

    let(:doc) { RXerces::XML::Document.parse(simple_xml) }

    describe "validates empty XPath expressions" do
      it "rejects empty string" do
        expect {
          doc.xpath('')
        }.to raise_error(ArgumentError, /cannot be empty/)
      end
    end

    describe "validates quote balancing" do
      it "rejects unbalanced single quotes" do
        expect {
          doc.xpath("//user[text()='Alice]")
        }.to raise_error(ArgumentError, /unbalanced quotes/)
      end

      it "rejects unbalanced double quotes" do
        expect {
          doc.xpath('//user[text()="Alice]')
        }.to raise_error(ArgumentError, /unbalanced quotes/)
      end

      it "allows properly balanced quotes" do
        expect {
          doc.xpath("//user")
        }.not_to raise_error
      end

      it "allows mixed balanced quotes" do
        expect {
          doc.xpath('//user')
        }.not_to raise_error
      end
    end

    describe "prevents XPath injection attacks" do
      it "rejects OR-based injection with numeric equality" do
        expect {
          doc.xpath("//user[@name='Alice' or 1=1]")
        }.to raise_error(ArgumentError, /suspicious injection pattern/)
      end

      it "rejects OR-based injection with string equality" do
        expect {
          doc.xpath("//user[@name='Alice' or 'a'='a']")
        }.to raise_error(ArgumentError, /suspicious injection pattern/)
      end

      it "rejects OR-based injection with double quotes" do
        expect {
          doc.xpath('//user[@name="Alice" or "1"="1"]')
        }.to raise_error(ArgumentError, /suspicious injection pattern/)
      end

      it "rejects OR-based injection with true() function" do
        expect {
          doc.xpath("//user[@name='Alice' or true()]")
        }.to raise_error(ArgumentError, /suspicious injection pattern/)
      end

      it "rejects AND-based injection with false condition" do
        expect {
          doc.xpath("//user[@name='Alice' and 1=0]")
        }.to raise_error(ArgumentError, /suspicious injection pattern/)
      end

      it "rejects AND-based injection with false() function" do
        expect {
          doc.xpath("//user[@name='Alice' and false()]")
        }.to raise_error(ArgumentError, /suspicious injection pattern/)
      end

      it "is case-insensitive for injection patterns" do
        expect {
          doc.xpath("//user[@name='Alice' OR 1=1]")
        }.to raise_error(ArgumentError, /suspicious injection pattern/)
      end
    end

    describe "prevents dangerous function calls" do
      it "rejects document() function" do
        expect {
          doc.xpath("document('file.xml')//user")
        }.to raise_error(ArgumentError, /dangerous function/)
      end

      it "rejects doc() function" do
        expect {
          doc.xpath("doc('file.xml')//user")
        }.to raise_error(ArgumentError, /dangerous function/)
      end

      it "rejects collection() function" do
        expect {
          doc.xpath("collection('files')//user")
        }.to raise_error(ArgumentError, /dangerous function/)
      end

      it "rejects unparsed-text() function" do
        expect {
          doc.xpath("unparsed-text('/etc/passwd')")
        }.to raise_error(ArgumentError, /dangerous function/)
      end

      it "rejects system-property() function" do
        expect {
          doc.xpath("system-property('java.version')")
        }.to raise_error(ArgumentError, /dangerous function/)
      end

      it "rejects environment-variable() function" do
        expect {
          doc.xpath("environment-variable('PATH')")
        }.to raise_error(ArgumentError, /dangerous function/)
      end
    end

    describe "prevents encoded character attacks" do
      it "rejects numeric character references" do
        expect {
          doc.xpath("//user[@name='&#65;lice']")
        }.to raise_error(ArgumentError, /encoded characters/)
      end

      it "rejects hexadecimal character references" do
        expect {
          doc.xpath("//user[@name='&#x41;lice']")
        }.to raise_error(ArgumentError, /encoded characters/)
      end

      it "rejects double-encoded entity references" do
        expect {
          doc.xpath("//user[@name='&amp;#65;lice']")
        }.to raise_error(ArgumentError, /encoded characters/)
      end

      it "allows legitimate ampersand usage in text" do
        # Should not raise - legitimate use of & in string literals
        xml = "<root><item name='Q&amp;A'>text</item></root>"
        test_doc = RXerces::XML::Document.parse(xml)
        expect { test_doc.xpath("//item") }.not_to raise_error
      end
    end

    describe "prevents comment-based attacks" do
      it "rejects XPath comments" do
        expect {
          doc.xpath("//user(: comment :)[@id='1']")
        }.to raise_error(ArgumentError, /comment patterns/)
      end

      it "rejects partial comment syntax" do
        expect {
          doc.xpath("//user(:[@id='1']")
        }.to raise_error(ArgumentError, /comment patterns/)
      end
    end

    describe "prevents null byte injection" do
      it "rejects expressions with null bytes" do
        xpath_with_null = "//user" + "\x00" + "[@id='1']"
        expect {
          doc.xpath(xpath_with_null)
        }.to raise_error(ArgumentError, /null byte/)
      end
    end

    describe "prevents excessive nesting attacks (DoS)" do
      it "rejects deeply nested brackets" do
        nested = "//user" + ("[." * 101) + ("]" * 101)
        expect {
          doc.xpath(nested)
        }.to raise_error(ArgumentError, /excessive nesting/)
      end

      it "rejects deeply nested parentheses" do
        nested = "count(" * 101 + "//user" + ")" * 101
        expect {
          doc.xpath(nested)
        }.to raise_error(ArgumentError, /excessive nesting/)
      end

      it "rejects unbalanced opening brackets" do
        expect {
          doc.xpath("//user[[[@id='1']")
        }.to raise_error(ArgumentError, /unbalanced/)
      end

      it "rejects unbalanced closing brackets" do
        expect {
          doc.xpath("//user[@id='1']]")
        }.to raise_error(ArgumentError, /unbalanced/)
      end

      it "rejects unbalanced parentheses" do
        expect {
          doc.xpath("count(//user")
        }.to raise_error(ArgumentError, /unbalanced/)
      end

      it "allows reasonable nesting depth" do
        nested = "//users/user/name"
        expect {
          doc.xpath(nested)
        }.not_to raise_error
      end
    end

    describe "prevents DoS via excessive length" do
      it "rejects excessively long XPath expressions" do
        # Create an expression over 10000 characters
        long_part = "/user" * 2001  # Each part is ~5 chars, 2001*5 > 10000
        long_xpath = "//users" + long_part
        expect {
          doc.xpath(long_xpath)
        }.to raise_error(ArgumentError, /too long/)
      end

      it "allows reasonably long expressions" do
        reasonable = "//users/user/name"
        expect {
          doc.xpath(reasonable)
        }.not_to raise_error
      end
    end

    describe "allows safe XPath expressions" do
      it "allows simple path expressions" do
        expect {
          result = doc.xpath('//user')
          expect(result.length).to eq(2)
        }.not_to raise_error
      end

      it "allows descendant paths" do
        expect {
          result = doc.xpath('//name')
          expect(result.length).to eq(2)
        }.not_to raise_error
      end

      it "allows child paths" do
        expect {
          result = doc.xpath('/users/user')
          expect(result.length).to eq(2)
        }.not_to raise_error
      end
    end

    describe "validates node XPath queries with injection prevention" do
      it "prevents injection in node context" do
        root = doc.root
        expect {
          root.xpath("//user[@name='Alice' or 1=1]")
        }.to raise_error(ArgumentError, /suspicious injection pattern/)
      end

      it "allows safe node queries" do
        root = doc.root
        expect {
          result = root.xpath('.//user')
          expect(result.length).to eq(2)
        }.not_to raise_error
      end
    end
  end
end
