## 0.7.0 - 3-Jan-2026
* Added XPath validation to prevent XPath injection attacks, with checks for
  unbalanced quotes, dangerous functions, encoded characters, and injection patterns.
* Added XPath validation caching with LRU eviction for better performance.
* Added configuration API for XPath validation caching.
* Added configurable XPath expression maximum length.
* Added RXerces.xalan_enabled? method to check Xalan availability.
* Added Node#attribute_nodes method to get attribute nodes as an array.
* Improved thread safety with mutex protection for Xerces/Xalan initialization.
* Added XXE (XML External Entity) protection, disabled by default.
* Improved exception handling with more specific error messages.
* Fixed UTF-8 truncation issues in NodeSet#inspect.
* Nodes are now automatically imported when adding children from different documents.
* Added validation for Document.parse options hash.
* Improved wrap_node function robustness.
* Now uses mkmf-lite to check for Xalan installation.

## 0.6.1 - 20-Dec-2025
* Added more Nokogiri compatibility methods: children, first_element_child,
  last_element_child, elements, at_xpath.

## 0.6.0 - 17-Dec-2025
* Some internal refactoring, better initialization, some better string
  handling, that sort of stuff.
* Added the Document#errors method with more detailed information. Also
  helps with Nokogiri compatibility.
* Added some benchmarks (they're not great compared to others, oh well).

## 0.5.0 - 16-Dec-2025
* Implemented a real css method. Requires Xalan to be installed.
* Added text/content methods for most classes.
* Added a nicer inspect method for most classes.
* Added an HTML alias for XML, mainly for compatibility with nokogiri,
  but keep in mind that this library parses HTML as XML.
* Added the Node#ancestors method.
* Added the Node#has_attribute method.
* Added first, last, empty? and inner_html methods for Node.
* Added elements, next_element and previous_element for Node.
* Added the Document#at_css method.

## 0.4.0 - 15-Dec-2025
* Now uses Xalan if installed for xpath 1.0 compliance.
* Added Node#search.
* Added Node#at and Node#at_xpath.
* Added Document#encoding.
* Added Node#namespace.
* Added a placeholder css method for now, it's on the TODO list.

## 0.3.0 - 14-Dec-2025
* Added Node#parent.
* Added Element#attributes.
* Added Node#next_node and Node#next_sibling.
* Added Node#previous_node and Node#previous_sibling.
* Added Element#add_child.
* Added Node#remove and Node#unlink.
* Added Document#create_element.
* Added Element#inner_xml and Element#inner_html.
* Added Node#path.
* Added Node#blank?

## 0.2.0 - 13-Dec-2025
* The nokogiri compatibility layer is now optional.
* Fixed up the gemspec with real values instead of the AI generated junk.
* Updated the Rakefile a bit, reworked some of the tasks.
* Minor spec updates.
* Added my cert.

## 0.1.0 - 12-Dec-2025
* Initial release.
