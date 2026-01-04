#include "rxerces.h"
#include <ruby/encoding.h>
#include <xercesc/util/PlatformUtils.hpp>
#include <xercesc/parsers/XercesDOMParser.hpp>
#include <xercesc/dom/DOM.hpp>
#include <xercesc/util/XMLString.hpp>
#include <xercesc/util/XMLUni.hpp>
#include <xercesc/framework/MemBufInputSource.hpp>
#include <xercesc/framework/MemBufFormatTarget.hpp>
#include <xercesc/util/XercesDefs.hpp>
#include <xercesc/dom/DOMXPathResult.hpp>
#include <xercesc/dom/DOMXPathExpression.hpp>
#include <xercesc/sax/ErrorHandler.hpp>
#include <xercesc/sax/SAXParseException.hpp>
#include <xercesc/sax/SAXException.hpp>
#include <sstream>
#include <vector>
#include <mutex>
#include <list>
#include <unordered_map>

#ifdef HAVE_XALAN
#include <xalanc/XPath/XPathEvaluator.hpp>
#include <xalanc/XPath/NodeRefList.hpp>
#include <xalanc/XPath/XObject.hpp>
#include <xalanc/XPath/XObjectFactoryDefault.hpp>
#include <xalanc/XPath/XPathEnvSupportDefault.hpp>
#include <xalanc/XPath/XPathExecutionContextDefault.hpp>
#include <xalanc/XPath/XPathConstructionContextDefault.hpp>
#include <xalanc/XPath/ElementPrefixResolverProxy.hpp>
#include <xalanc/XPath/XPathFactoryDefault.hpp>
#include <xalanc/XPath/XPathProcessorImpl.hpp>
#include <xalanc/XPath/XPath.hpp>
#include <xalanc/XercesParserLiaison/XercesParserLiaison.hpp>
#include <xalanc/XercesParserLiaison/XercesDOMSupport.hpp>
#include <xalanc/XercesParserLiaison/XercesDocumentWrapper.hpp>
#include <xalanc/PlatformSupport/XalanMemoryManagerDefault.hpp>
#endif

using namespace xercesc;
#ifdef HAVE_XALAN
using namespace xalanc;
#endif

VALUE rb_mRXerces;
VALUE rb_mXML;
VALUE rb_cDocument;
VALUE rb_cNode;
VALUE rb_cNodeSet;
VALUE rb_cElement;
VALUE rb_cText;
VALUE rb_cSchema;

// Initialization flags
static bool xerces_initialized = false;
#ifdef HAVE_XALAN
static bool xalan_initialized = false;
#endif
static std::mutex init_mutex;

// XPath validation cache with LRU eviction
// Uses a list for LRU ordering (front = most recently used)
// and a map for O(1) lookup of list iterators
static std::list<std::string>* xpath_cache_lru_list = nullptr;
static std::unordered_map<std::string, std::list<std::string>::iterator>* xpath_cache_map = nullptr;
static std::mutex xpath_cache_mutex;
static bool cache_xpath_validation = true;  // Default: enabled
static size_t xpath_cache_max_size = 10000; // Max cached expressions
static size_t xpath_max_length = 10000;     // Max XPath expression length

#ifdef HAVE_XALAN
// Cached Xalan context per document for XPath performance
// This avoids recreating expensive Xalan infrastructure on every XPath query
struct XalanContext {
    XercesParserLiaison* liaison;
    XercesDOMSupport* domSupport;
    XalanDocument* xalanDoc;
    XercesDocumentWrapper* docWrapper;
    XPathEnvSupportDefault* envSupport;
    XObjectFactoryDefault* objectFactory;
    XPathExecutionContextDefault* executionContext;
    XPathConstructionContextDefault* constructionContext;
    XPathFactoryDefault* factory;
    XPathProcessorImpl* processor;

    XalanContext() : liaison(nullptr), domSupport(nullptr), xalanDoc(nullptr),
                     docWrapper(nullptr), envSupport(nullptr), objectFactory(nullptr),
                     executionContext(nullptr), constructionContext(nullptr),
                     factory(nullptr), processor(nullptr) {}

    ~XalanContext() {
        // Clean up in reverse order of creation
        delete executionContext;
        delete constructionContext;
        delete objectFactory;
        delete envSupport;
        delete factory;
        delete processor;
        // domSupport must be deleted before liaison
        delete domSupport;
        // liaison owns xalanDoc/docWrapper, so don't delete them separately
        delete liaison;
    }
};

// Compiled XPath expression cache per document
struct CompiledXPath {
    XPath* xpath;
    std::string expression;

    CompiledXPath(XPath* x, const std::string& expr) : xpath(x), expression(expr) {}
};

// LRU cache for compiled XPath expressions
static const size_t XPATH_COMPILE_CACHE_SIZE = 100;
#endif

// Forward declarations
static std::string css_to_xpath(const char* css);
static VALUE node_css(VALUE self, VALUE selector);
static VALUE node_xpath(VALUE self, VALUE path);
static VALUE document_xpath(VALUE self, VALUE path);

// Initialize Xerces (and Xalan if available) exactly once
static void ensure_xerces_initialized() {
    if (xerces_initialized) {
        return;
    }

    std::lock_guard<std::mutex> lock(init_mutex);

    if (xerces_initialized) {
        return;
    }

    try {
        XMLPlatformUtils::Initialize();
#ifdef HAVE_XALAN
        XPathEvaluator::initialize();
        xalan_initialized = true;
#endif
        xerces_initialized = true;
    } catch (const XMLException& e) {
        char* message = XMLString::transcode(e.getMessage());
        std::string error_msg = std::string("Xerces initialization failed: ") + message;
        XMLString::release(&message);
        rb_raise(rb_eRuntimeError, "%s", error_msg.c_str());
    }
}

// Cleanup function called at exit
static void cleanup_xerces() {
    // Clean up XPath validation cache (LRU)
    if (xpath_cache_lru_list) {
        delete xpath_cache_lru_list;
        xpath_cache_lru_list = nullptr;
    }
    if (xpath_cache_map) {
        delete xpath_cache_map;
        xpath_cache_map = nullptr;
    }

#ifdef HAVE_XALAN
    if (xalan_initialized) {
        XPathEvaluator::terminate();
        xalan_initialized = false;
    }
#endif
    if (xerces_initialized) {
        XMLPlatformUtils::Terminate();
        xerces_initialized = false;
    }
}

// Validate XPath expression to prevent XPath injection attacks
static void validate_xpath_expression(const char* xpath_str) {
    if (!xpath_str || strlen(xpath_str) == 0) {
        rb_raise(rb_eArgError, "XPath expression cannot be empty");
    }

    std::string xpath(xpath_str);

    // Check cache first if caching is enabled (LRU cache)
    if (cache_xpath_validation) {
        std::lock_guard<std::mutex> lock(xpath_cache_mutex);
        if (!xpath_cache_lru_list) {
            xpath_cache_lru_list = new std::list<std::string>();
        }
        if (!xpath_cache_map) {
            xpath_cache_map = new std::unordered_map<std::string, std::list<std::string>::iterator>();
        }
        auto it = xpath_cache_map->find(xpath);
        if (it != xpath_cache_map->end()) {
            // Cache hit: move to front (most recently used)
            xpath_cache_lru_list->splice(xpath_cache_lru_list->begin(), *xpath_cache_lru_list, it->second);
            return; // Already validated
        }
    }
    size_t len = xpath.length();

    // Check for excessively long XPath expressions (potential DoS)
    if (xpath_max_length > 0 && len > xpath_max_length) {
        rb_raise(rb_eArgError, "XPath expression is too long (max %zu characters)", xpath_max_length);
    }

    // Check for dangerous patterns that could indicate XPath injection
    // These patterns are commonly used in XPath injection attacks

    // 1. Check for unbalanced quotes which could break out of string literals
    int single_quotes = 0;
    int double_quotes = 0;
    bool in_single_quote = false;
    bool in_double_quote = false;

    for (size_t i = 0; i < len; i++) {
        char c = xpath[i];

        // Track quote state
        if (c == '\'' && !in_double_quote) {
            in_single_quote = !in_single_quote;
            single_quotes++;
        } else if (c == '"' && !in_single_quote) {
            in_double_quote = !in_double_quote;
            double_quotes++;
        }
    }

    // Unbalanced quotes are suspicious
    if (single_quotes % 2 != 0 || double_quotes % 2 != 0) {
        rb_raise(rb_eArgError, "XPath expression contains unbalanced quotes");
    }

    // 2. Check for suspicious comment patterns that could be used to bypass validation
    if (xpath.find("(:") != std::string::npos || xpath.find(":)") != std::string::npos) {
        rb_raise(rb_eArgError, "XPath expression contains suspicious comment patterns");
    }

    // 3. Check for null bytes which could truncate validation
    if (xpath.find('\0') != std::string::npos) {
        rb_raise(rb_eArgError, "XPath expression contains null bytes");
    }

    // 4. Check for excessive nesting which could cause stack overflow
    int bracket_depth = 0;
    int paren_depth = 0;
    const int MAX_DEPTH = 100;

    for (size_t i = 0; i < len; i++) {
        char c = xpath[i];

        if (c == '[') bracket_depth++;
        else if (c == ']') bracket_depth--;
        else if (c == '(') paren_depth++;
        else if (c == ')') paren_depth--;

        if (bracket_depth > MAX_DEPTH || paren_depth > MAX_DEPTH) {
            rb_raise(rb_eArgError, "XPath expression has excessive nesting depth");
        }

        if (bracket_depth < 0 || paren_depth < 0) {
            rb_raise(rb_eArgError, "XPath expression has unbalanced brackets or parentheses");
        }
    }

    if (bracket_depth != 0 || paren_depth != 0) {
        rb_raise(rb_eArgError, "XPath expression has unbalanced brackets or parentheses");
    }

    // 5. Check for suspicious function calls that could access system functions
    // or perform dangerous operations
    std::vector<std::string> dangerous_patterns = {
        "document(",       // Can access external documents
        "doc(",            // Can access external documents
        "collection(",     // Can access external collections
        "unparsed-text(", // Can read arbitrary files
        "system-property(", // Can leak system information
        "environment-variable(", // Can leak environment variables
    };

    for (const auto& pattern : dangerous_patterns) {
        if (xpath.find(pattern) != std::string::npos) {
            rb_raise(rb_eArgError, "XPath expression contains potentially dangerous function: %s", pattern.c_str());
        }
    }

    // 6. Check for encoded characters that could bypass validation
    // Use specific patterns to avoid false positives (e.g., "Q&A" in text)
    if (xpath.find("&#") != std::string::npos ||    // Numeric character reference (&#60;)
        xpath.find("&#x") != std::string::npos ||   // Hex character reference (&#x3C;)
        xpath.find("&amp;#") != std::string::npos) { // Encoded entity reference
        rb_raise(rb_eArgError, "XPath expression contains encoded characters");
    }

    // 7. Detect potential boolean-based blind XPath injection patterns
    // These patterns use 'or' with always-true conditions
    std::vector<std::string> injection_patterns = {
        "or 1=1",
        "or '1'='1'",
        "or \"1\"=\"1\"",
        "or true()",
        "and 1=0",
        "and false()",
        "or 'a'='a'",
        "or \"a\"=\"a\"",
    };

    // Convert to lowercase for case-insensitive comparison
    std::string xpath_lower = xpath;
    std::transform(xpath_lower.begin(), xpath_lower.end(), xpath_lower.begin(), ::tolower);

    for (const auto& pattern : injection_patterns) {
        if (xpath_lower.find(pattern) != std::string::npos) {
            rb_raise(rb_eArgError, "XPath expression contains suspicious injection pattern");
        }
    }

    // Add to cache if caching is enabled (LRU eviction)
    if (cache_xpath_validation) {
        std::lock_guard<std::mutex> lock(xpath_cache_mutex);
        if (xpath_cache_lru_list && xpath_cache_map) {
            // If cache is full, evict least recently used (back of list)
            if (xpath_cache_max_size > 0 && xpath_cache_map->size() >= xpath_cache_max_size) {
                std::string& lru = xpath_cache_lru_list->back();
                xpath_cache_map->erase(lru);
                xpath_cache_lru_list->pop_back();
            }
            // Add new entry to front (most recently used)
            if (xpath_cache_max_size > 0) {
                xpath_cache_lru_list->push_front(xpath);
                (*xpath_cache_map)[xpath] = xpath_cache_lru_list->begin();
            }
        }
    }
}

// Helper class to manage XMLCh strings
class XStr {
public:
    XStr(const char* const toTranscode) {
        fUnicodeForm = XMLString::transcode(toTranscode);
    }

    XStr(const std::string& toTranscode) {
        fUnicodeForm = XMLString::transcode(toTranscode.c_str());
    }

    ~XStr() {
        XMLString::release(&fUnicodeForm);
    }

    const XMLCh* unicodeForm() const {
        return fUnicodeForm;
    }

private:
    XMLCh* fUnicodeForm;
};

// Helper to convert XMLCh to char*
class CharStr {
public:
    CharStr(const XMLCh* const toTranscode) {
        fLocalForm = XMLString::transcode(toTranscode);
    }

    ~CharStr() {
        XMLString::release(&fLocalForm);
    }

    const char* localForm() const {
        return fLocalForm;
    }

private:
    char* fLocalForm;
};

// Wrapper structure for DOMDocument
typedef struct {
    DOMDocument* doc;
    XercesDOMParser* parser;
    std::vector<std::string>* parse_errors;
#ifdef HAVE_XALAN
    XalanContext* xalan_context;  // Cached Xalan context for XPath performance
    std::list<CompiledXPath*>* xpath_cache_list;  // LRU list of compiled expressions
    std::unordered_map<std::string, std::list<CompiledXPath*>::iterator>* xpath_cache_map;
#endif
} DocumentWrapper;

// Wrapper structure for DOMNode
typedef struct {
    DOMNode* node;
    VALUE doc_ref; // Keep reference to parent document
} NodeWrapper;

// Wrapper structure for NodeSet (array of nodes)
typedef struct {
    VALUE nodes_array;
} NodeSetWrapper;

// Wrapper structure for Schema
typedef struct {
    std::string* schemaContent;
} SchemaWrapper;

// Error handler for schema validation
class ValidationErrorHandler : public ErrorHandler {
public:
    std::vector<std::string> errors;

    void warning(const SAXParseException& e) {
        char* msg = XMLString::transcode(e.getMessage());
        char buffer[512];
        snprintf(buffer, sizeof(buffer), "Warning at line %lu, column %lu: %s",
                 (unsigned long)e.getLineNumber(),
                 (unsigned long)e.getColumnNumber(),
                 msg);
        errors.push_back(buffer);
        XMLString::release(&msg);
    }

    void error(const SAXParseException& e) {
        char* msg = XMLString::transcode(e.getMessage());
        char buffer[512];
        snprintf(buffer, sizeof(buffer), "Error at line %lu, column %lu: %s",
                 (unsigned long)e.getLineNumber(),
                 (unsigned long)e.getColumnNumber(),
                 msg);
        errors.push_back(buffer);
        XMLString::release(&msg);
    }

    void fatalError(const SAXParseException& e) {
        char* msg = XMLString::transcode(e.getMessage());
        char buffer[512];
        snprintf(buffer, sizeof(buffer), "Fatal error at line %lu, column %lu: %s",
                 (unsigned long)e.getLineNumber(),
                 (unsigned long)e.getColumnNumber(),
                 msg);
        errors.push_back(buffer);
        XMLString::release(&msg);
    }

    void resetErrors() {
        errors.clear();
    }
};

// Error handler for parsing - stores errors but doesn't throw
class ParseErrorHandler : public ErrorHandler {
public:
    std::vector<std::string>* errors;
    bool has_fatal;

    ParseErrorHandler(std::vector<std::string>* error_vec)
        : errors(error_vec), has_fatal(false) {}

    void warning(const SAXParseException& e) {
        char* msg = XMLString::transcode(e.getMessage());
        char buffer[512];
        snprintf(buffer, sizeof(buffer), "Warning at line %lu, column %lu: %s",
                 (unsigned long)e.getLineNumber(),
                 (unsigned long)e.getColumnNumber(),
                 msg);
        errors->push_back(buffer);
        XMLString::release(&msg);
    }

    void error(const SAXParseException& e) {
        char* msg = XMLString::transcode(e.getMessage());
        char buffer[512];
        snprintf(buffer, sizeof(buffer), "Error at line %lu, column %lu: %s",
                 (unsigned long)e.getLineNumber(),
                 (unsigned long)e.getColumnNumber(),
                 msg);
        errors->push_back(buffer);
        XMLString::release(&msg);
    }

    void fatalError(const SAXParseException& e) {
        has_fatal = true;
        char* msg = XMLString::transcode(e.getMessage());
        char buffer[512];
        snprintf(buffer, sizeof(buffer), "Fatal error at line %lu, column %lu: %s",
                 (unsigned long)e.getLineNumber(),
                 (unsigned long)e.getColumnNumber(),
                 msg);
        errors->push_back(buffer);
        XMLString::release(&msg);
    }

    void resetErrors() {
        errors->clear();
        has_fatal = false;
    }
};

// Memory management functions
static void document_free(void* ptr) {
    DocumentWrapper* wrapper = (DocumentWrapper*)ptr;
    if (wrapper) {
#ifdef HAVE_XALAN
        // Clean up XPath cache first
        if (wrapper->xpath_cache_list) {
            for (auto& compiled : *wrapper->xpath_cache_list) {
                if (compiled && compiled->xpath && wrapper->xalan_context && wrapper->xalan_context->factory) {
                    wrapper->xalan_context->factory->returnObject(compiled->xpath);
                }
                delete compiled;
            }
            delete wrapper->xpath_cache_list;
        }
        if (wrapper->xpath_cache_map) {
            delete wrapper->xpath_cache_map;
        }
        // Clean up Xalan context
        if (wrapper->xalan_context) {
            delete wrapper->xalan_context;
        }
#endif
        if (wrapper->parser) {
            delete wrapper->parser;
        }
        if (wrapper->parse_errors) {
            delete wrapper->parse_errors;
        }
        // Document is owned by parser, so don't delete it separately
        xfree(wrapper);
    }
}

static void node_free(void* ptr) {
    NodeWrapper* wrapper = (NodeWrapper*)ptr;
    if (wrapper) {
        // Don't delete node - it's owned by the document
        xfree(wrapper);
    }
}

static void node_mark(void* ptr) {
    NodeWrapper* wrapper = (NodeWrapper*)ptr;
    if (wrapper) {
        rb_gc_mark(wrapper->doc_ref);
    }
}

static void nodeset_free(void* ptr) {
    NodeSetWrapper* wrapper = (NodeSetWrapper*)ptr;
    if (wrapper) {
        xfree(wrapper);
    }
}

static void nodeset_mark(void* ptr) {
    NodeSetWrapper* wrapper = (NodeSetWrapper*)ptr;
    if (wrapper) {
        rb_gc_mark(wrapper->nodes_array);
    }
}

static void schema_free(void* ptr) {
    SchemaWrapper* wrapper = (SchemaWrapper*)ptr;
    if (wrapper) {
        if (wrapper->schemaContent) {
            delete wrapper->schemaContent;
        }
        xfree(wrapper);
    }
}

static size_t document_size(const void* ptr) {
    return sizeof(DocumentWrapper);
}

static size_t node_size(const void* ptr) {
    return sizeof(NodeWrapper);
}

static size_t nodeset_size(const void* ptr) {
    return sizeof(NodeSetWrapper);
}

static size_t schema_size(const void* ptr) {
    return sizeof(SchemaWrapper);
}

static const rb_data_type_t document_type = {
    "RXerces::XML::Document",
    {0, document_free, document_size},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY
};

static const rb_data_type_t node_type = {
    "RXerces::XML::Node",
    {node_mark, node_free, node_size},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY
};

static const rb_data_type_t nodeset_type = {
    "RXerces::XML::NodeSet",
    {nodeset_mark, nodeset_free, nodeset_size},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY
};

static const rb_data_type_t schema_type = {
    "RXerces::XML::Schema",
    {0, schema_free, schema_size},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY
};

// Helper to create Ruby Node object from DOMNode
static VALUE wrap_node(DOMNode* node, VALUE doc_ref) {
    if (!node) {
        return Qnil;
    }

    VALUE rb_class;
    switch (node->getNodeType()) {
        case DOMNode::ELEMENT_NODE:
            rb_class = rb_cElement;
            break;
        case DOMNode::TEXT_NODE:
            rb_class = rb_cText;
            break;
        default:
            rb_class = rb_cNode;
            break;
    }

    VALUE rb_node = TypedData_Wrap_Struct(rb_class, &node_type, NULL);
    NodeWrapper* wrapper = ALLOC(NodeWrapper);
    wrapper->node = node;
    wrapper->doc_ref = doc_ref;
    DATA_PTR(rb_node) = wrapper;

    return rb_node;
}

// RXerces::XML::Document.parse(string, options = {})
// Validate options hash for document_parse - only allow known keys
static void validate_parse_options(VALUE options) {
    if (NIL_P(options)) {
        return;
    }

    Check_Type(options, T_HASH);

    // Define allowed option keys
    std::vector<const char*> allowed_keys = {
        "allow_external_entities"
    };

    // Get all keys from the provided options hash
    VALUE keys = rb_funcall(options, rb_intern("keys"), 0);
    long keys_len = RARRAY_LEN(keys);

    // Check each key against the allowed list
    for (long i = 0; i < keys_len; i++) {
        VALUE key = rb_ary_entry(keys, i);

        // Convert symbol or string key to string for comparison
        VALUE key_str;
        if (TYPE(key) == T_SYMBOL) {
            key_str = rb_sym_to_s(key);
        } else if (TYPE(key) == T_STRING) {
            key_str = key;
        } else {
            rb_raise(rb_eArgError, "Option keys must be symbols or strings");
        }

        const char* key_cstr = StringValueCStr(key_str);
        bool found = false;

        for (const auto& allowed : allowed_keys) {
            if (strcmp(key_cstr, allowed) == 0) {
                found = true;
                break;
            }
        }

        if (!found) {
            rb_raise(rb_eArgError, "Unknown option: %s. Allowed options are: allow_external_entities", key_cstr);
        }
    }
}

static VALUE document_parse(int argc, VALUE* argv, VALUE klass) {
    VALUE str, options;
    rb_scan_args(argc, argv, "11", &str, &options);

    ensure_xerces_initialized();

    Check_Type(str, T_STRING);
    const char* xml_str = StringValueCStr(str);

    // Validate options hash before processing
    validate_parse_options(options);

    XercesDOMParser* parser = new XercesDOMParser();

    // Check if external entities should be allowed (default: false for security)
    bool allow_external = false;
    if (!NIL_P(options)) {
        VALUE allow_key = rb_intern("allow_external_entities");
        VALUE allow_val = rb_hash_aref(options, ID2SYM(allow_key));
        if (RTEST(allow_val)) {
            allow_external = true;
        }
    }

    if (allow_external) {
        // Allow external entities (less secure)
        parser->setLoadExternalDTD(true);
        parser->setDisableDefaultEntityResolution(false);
    } else {
        // Security: Disable external entity processing to prevent XXE attacks
        parser->setLoadExternalDTD(false);
        parser->setDisableDefaultEntityResolution(true);
    }

    parser->setValidationScheme(XercesDOMParser::Val_Never);
    parser->setDoNamespaces(true);
    parser->setDoSchema(false);

    // Set up error handler to capture parse errors
    std::vector<std::string>* parse_errors = new std::vector<std::string>();
    ParseErrorHandler error_handler(parse_errors);
    parser->setErrorHandler(&error_handler);

    try {
        MemBufInputSource input((const XMLByte*)xml_str, strlen(xml_str), "memory");
        parser->parse(input);

        DOMDocument* doc = parser->getDocument();

        DocumentWrapper* wrapper = ALLOC(DocumentWrapper);
        wrapper->doc = doc;
        wrapper->parser = parser;
        wrapper->parse_errors = parse_errors;
#ifdef HAVE_XALAN
        wrapper->xalan_context = nullptr;  // Lazily initialized on first XPath query
        wrapper->xpath_cache_list = nullptr;
        wrapper->xpath_cache_map = nullptr;
#endif

        VALUE rb_doc = TypedData_Wrap_Struct(rb_cDocument, &document_type, wrapper);

        // If there were fatal errors, raise an exception with details
        if (error_handler.has_fatal && !parse_errors->empty()) {
            std::string all_errors;
            for (const auto& err : *parse_errors) {
                if (!all_errors.empty()) all_errors += "\n";
                all_errors += err;
            }
            rb_raise(rb_eRuntimeError, "XML parsing failed:\n%s", all_errors.c_str());
        }

        return rb_doc;
    } catch (const XMLException& e) {
        CharStr message(e.getMessage());
        delete parse_errors;
        delete parser;
        rb_raise(rb_eRuntimeError, "XML parsing error: %s", message.localForm());
    } catch (const DOMException& e) {
        CharStr message(e.getMessage());
        delete parse_errors;
        delete parser;
        rb_raise(rb_eRuntimeError, "DOM error: %s", message.localForm());
    } catch (...) {
        delete parse_errors;
        delete parser;
        rb_raise(rb_eRuntimeError, "Unknown XML parsing error");
    }

    return Qnil;
}

// document.errors - returns array of parse errors (warnings and errors)
static VALUE document_errors(VALUE self) {
    DocumentWrapper* wrapper;
    TypedData_Get_Struct(self, DocumentWrapper, &document_type, wrapper);

    VALUE errors_array = rb_ary_new();

    if (wrapper->parse_errors) {
        for (const auto& error : *wrapper->parse_errors) {
            rb_ary_push(errors_array, rb_str_new2(error.c_str()));
        }
    }

    return errors_array;
}

// document.root
static VALUE document_root(VALUE self) {
    DocumentWrapper* wrapper;
    TypedData_Get_Struct(self, DocumentWrapper, &document_type, wrapper);

    if (!wrapper->doc) {
        return Qnil;
    }

    DOMElement* root = wrapper->doc->getDocumentElement();
    return wrap_node(root, self);
}

// document.to_s / document.to_xml
static VALUE document_to_s(VALUE self) {
    DocumentWrapper* wrapper;
    TypedData_Get_Struct(self, DocumentWrapper, &document_type, wrapper);

    if (!wrapper->doc) {
        return rb_str_new_cstr("");
    }

    try {
        DOMImplementation* impl = DOMImplementationRegistry::getDOMImplementation(XStr("LS").unicodeForm());
        DOMLSSerializer* serializer = ((DOMImplementationLS*)impl)->createLSSerializer();

        XMLCh* xml_str = serializer->writeToString(wrapper->doc);
        CharStr utf8_str(xml_str);

        VALUE result = rb_str_new_cstr(utf8_str.localForm());

        XMLString::release(&xml_str);
        serializer->release();

        return result;
    } catch (const DOMException& e) {
        CharStr message(e.getMessage());
        rb_raise(rb_eRuntimeError, "Failed to serialize document: %s", message.localForm());
    } catch (const XMLException& e) {
        CharStr message(e.getMessage());
        rb_raise(rb_eRuntimeError, "Failed to serialize document (XMLException): %s", message.localForm());
    } catch (const std::exception& e) {
        rb_raise(rb_eRuntimeError, "Failed to serialize document (std::exception): %s", e.what());
    } catch (...) {
        rb_raise(rb_eRuntimeError, "Failed to serialize document (unknown exception type)");
    }

    return Qnil;
}

// document.inspect - human-readable representation
static VALUE document_inspect(VALUE self) {
    DocumentWrapper* wrapper;
    TypedData_Get_Struct(self, DocumentWrapper, &document_type, wrapper);

    std::string result = "#<RXerces::XML::Document:0x";

    // Add object ID
    char buf[32];
    snprintf(buf, sizeof(buf), "%016lx", (unsigned long)self);
    result += buf;

    if (!wrapper->doc) {
        result += " (empty)>";
        return rb_str_new_cstr(result.c_str());
    }

    // Add encoding
    const XMLCh* encoding = wrapper->doc->getXmlEncoding();
    if (encoding && XMLString::stringLen(encoding) > 0) {
        CharStr utf8_encoding(encoding);
        result += " encoding=\"";
        result += utf8_encoding.localForm();
        result += "\"";
    }

    // Add root element name
    DOMElement* root = wrapper->doc->getDocumentElement();
    if (root) {
        CharStr rootName(root->getNodeName());
        result += " root=<";
        result += rootName.localForm();
        result += ">";
    }

    result += ">";
    return rb_str_new_cstr(result.c_str());
}

// document.encoding
static VALUE document_encoding(VALUE self) {
    DocumentWrapper* wrapper;
    TypedData_Get_Struct(self, DocumentWrapper, &document_type, wrapper);

    if (!wrapper->doc) {
        return Qnil;
    }

    const XMLCh* encoding = wrapper->doc->getXmlEncoding();
    if (!encoding || XMLString::stringLen(encoding) == 0) {
        // Default to UTF-8 if no encoding is specified
        return rb_str_new_cstr("UTF-8");
    }

    CharStr utf8_encoding(encoding);
    return rb_str_new_cstr(utf8_encoding.localForm());
}

// document.text / document.content - returns text content of entire document
static VALUE document_text(VALUE self) {
    DocumentWrapper* wrapper;
    TypedData_Get_Struct(self, DocumentWrapper, &document_type, wrapper);

    if (!wrapper->doc) {
        return rb_str_new_cstr("");
    }

    DOMElement* root = wrapper->doc->getDocumentElement();
    if (!root) {
        return rb_str_new_cstr("");
    }

    const XMLCh* content = root->getTextContent();
    if (!content) {
        return rb_str_new_cstr("");
    }

    CharStr utf8_content(content);
    return rb_str_new_cstr(utf8_content.localForm());
}

// document.create_element(name)
static VALUE document_create_element(VALUE self, VALUE name) {
    DocumentWrapper* doc_wrapper;
    TypedData_Get_Struct(self, DocumentWrapper, &document_type, doc_wrapper);

    if (!doc_wrapper->doc) {
        rb_raise(rb_eRuntimeError, "Cannot create element on null document");
    }

    Check_Type(name, T_STRING);
    const char* element_name = StringValueCStr(name);

    try {
        XMLCh* element_name_xml = XMLString::transcode(element_name);
        DOMElement* element = doc_wrapper->doc->createElement(element_name_xml);
        XMLString::release(&element_name_xml);

        if (!element) {
            rb_raise(rb_eRuntimeError, "Failed to create element");
        }

        return wrap_node(element, self);

    } catch (const DOMException& e) {
        char* message = XMLString::transcode(e.getMessage());
        VALUE rb_error = rb_str_new_cstr(message);
        XMLString::release(&message);
        rb_raise(rb_eRuntimeError, "Failed to create element: %s", StringValueCStr(rb_error));
    } catch (...) {
        rb_raise(rb_eRuntimeError, "Unknown error creating element");
    }

    return Qnil;
}

// document.children - returns all children (elements, text, comments, etc.)
static VALUE document_children(VALUE self) {
    DocumentWrapper* wrapper;
    TypedData_Get_Struct(self, DocumentWrapper, &document_type, wrapper);

    if (!wrapper->doc) {
        return rb_ary_new();
    }

    DOMNodeList* child_nodes = wrapper->doc->getChildNodes();
    XMLSize_t count = child_nodes->getLength();

    // Pre-size array for better performance
    VALUE children = rb_ary_new_capa((long)count);

    for (XMLSize_t i = 0; i < count; i++) {
        DOMNode* child = child_nodes->item(i);
        rb_ary_push(children, wrap_node(child, self));
    }

    return children;
}

// document.element_children - returns only element children (no text nodes, comments, etc.)
static VALUE document_element_children(VALUE self) {
    DocumentWrapper* wrapper;
    TypedData_Get_Struct(self, DocumentWrapper, &document_type, wrapper);

    if (!wrapper->doc) {
        return rb_ary_new();
    }

    DOMNodeList* child_nodes = wrapper->doc->getChildNodes();
    XMLSize_t count = child_nodes->getLength();

    // Pre-size array (may be smaller than count, but good estimate)
    VALUE children = rb_ary_new_capa((long)count);

    for (XMLSize_t i = 0; i < count; i++) {
        DOMNode* child = child_nodes->item(i);
        if (child->getNodeType() == DOMNode::ELEMENT_NODE) {
            rb_ary_push(children, wrap_node(child, self));
        }
    }

    return children;
}

// document.first_element_child - returns first element child
static VALUE document_first_element_child(VALUE self) {
    DocumentWrapper* wrapper;
    TypedData_Get_Struct(self, DocumentWrapper, &document_type, wrapper);

    if (!wrapper->doc) {
        return Qnil;
    }

    DOMNodeList* child_nodes = wrapper->doc->getChildNodes();
    XMLSize_t count = child_nodes->getLength();

    for (XMLSize_t i = 0; i < count; i++) {
        DOMNode* child = child_nodes->item(i);
        if (child->getNodeType() == DOMNode::ELEMENT_NODE) {
            return wrap_node(child, self);
        }
    }

    return Qnil;
}

// document.last_element_child - returns last element child
static VALUE document_last_element_child(VALUE self) {
    DocumentWrapper* wrapper;
    TypedData_Get_Struct(self, DocumentWrapper, &document_type, wrapper);

    if (!wrapper->doc) {
        return Qnil;
    }

    DOMNodeList* child_nodes = wrapper->doc->getChildNodes();
    XMLSize_t count = child_nodes->getLength();

    // Search backwards for last element
    for (XMLSize_t i = count; i > 0; i--) {
        DOMNode* child = child_nodes->item(i - 1);
        if (child->getNodeType() == DOMNode::ELEMENT_NODE) {
            return wrap_node(child, self);
        }
    }

    return Qnil;
}

#ifdef HAVE_XALAN
// Helper to initialize or get cached Xalan context for a document
static XalanContext* get_or_create_xalan_context(DocumentWrapper* doc_wrapper) {
    if (doc_wrapper->xalan_context) {
        return doc_wrapper->xalan_context;
    }

    // Create new context
    XalanContext* ctx = new XalanContext();

    try {
        ctx->liaison = new XercesParserLiaison();
        ctx->domSupport = new XercesDOMSupport(*ctx->liaison);

        // Create Xalan document wrapper - this is owned by liaison
        ctx->xalanDoc = ctx->liaison->createDocument(doc_wrapper->doc, false, false, false);
        if (!ctx->xalanDoc) {
            delete ctx;
            return nullptr;
        }
        ctx->docWrapper = static_cast<XercesDocumentWrapper*>(ctx->xalanDoc);

        // Create XPath infrastructure
        ctx->envSupport = new XPathEnvSupportDefault();
        ctx->objectFactory = new XObjectFactoryDefault();
        ctx->executionContext = new XPathExecutionContextDefault(*ctx->envSupport, *ctx->domSupport, *ctx->objectFactory);
        ctx->constructionContext = new XPathConstructionContextDefault();
        ctx->factory = new XPathFactoryDefault();
        ctx->processor = new XPathProcessorImpl();

        doc_wrapper->xalan_context = ctx;

        // Initialize XPath expression cache
        doc_wrapper->xpath_cache_list = new std::list<CompiledXPath*>();
        doc_wrapper->xpath_cache_map = new std::unordered_map<std::string, std::list<CompiledXPath*>::iterator>();

        return ctx;
    } catch (...) {
        delete ctx;
        return nullptr;
    }
}

// Get or compile XPath expression with LRU caching
static XPath* get_or_compile_xpath(DocumentWrapper* doc_wrapper, XalanContext* ctx, const char* xpath_str) {
    std::string expr(xpath_str);

    // Check cache
    auto it = doc_wrapper->xpath_cache_map->find(expr);
    if (it != doc_wrapper->xpath_cache_map->end()) {
        // Cache hit - move to front (most recently used)
        CompiledXPath* compiled = *(it->second);
        doc_wrapper->xpath_cache_list->erase(it->second);
        doc_wrapper->xpath_cache_list->push_front(compiled);
        (*doc_wrapper->xpath_cache_map)[expr] = doc_wrapper->xpath_cache_list->begin();
        return compiled->xpath;
    }

    // Cache miss - compile new XPath
    XPath* xpath = ctx->factory->create();

    // Get document element for resolver (can be null, that's ok)
    XalanElement* docElem = ctx->docWrapper->getDocumentElement();
    ElementPrefixResolverProxy resolver(docElem, *ctx->envSupport, *ctx->domSupport);
    ctx->processor->initXPath(*xpath, *ctx->constructionContext, XalanDOMString(xpath_str), resolver);

    // Add to cache
    CompiledXPath* compiled = new CompiledXPath(xpath, expr);
    doc_wrapper->xpath_cache_list->push_front(compiled);
    (*doc_wrapper->xpath_cache_map)[expr] = doc_wrapper->xpath_cache_list->begin();

    // Evict if cache is too large
    if (doc_wrapper->xpath_cache_list->size() > XPATH_COMPILE_CACHE_SIZE) {
        CompiledXPath* lru = doc_wrapper->xpath_cache_list->back();
        doc_wrapper->xpath_cache_map->erase(lru->expression);
        ctx->factory->returnObject(lru->xpath);
        delete lru;
        doc_wrapper->xpath_cache_list->pop_back();
    }

    return xpath;
}

// Helper function to execute XPath using Xalan for full XPath 1.0 support
// Uses cached Xalan context and compiled XPath expressions for performance
static VALUE execute_xpath_with_xalan(DOMNode* context_node, const char* xpath_str, VALUE doc_ref) {
    // Validate XPath expression before execution
    validate_xpath_expression(xpath_str);

    ensure_xerces_initialized();

    try {
        // Get the document wrapper
        DocumentWrapper* doc_wrapper;
        TypedData_Get_Struct(doc_ref, DocumentWrapper, &document_type, doc_wrapper);

        DOMDocument* domDoc = doc_wrapper->doc;
        if (!domDoc) {
            NodeSetWrapper* wrapper = ALLOC(NodeSetWrapper);
            wrapper->nodes_array = rb_ary_new();
            return TypedData_Wrap_Struct(rb_cNodeSet, &nodeset_type, wrapper);
        }

        // Get or create cached Xalan context
        XalanContext* ctx = get_or_create_xalan_context(doc_wrapper);
        if (!ctx) {
            rb_raise(rb_eRuntimeError, "Failed to create Xalan context");
        }

        // Map the context node to Xalan
        XalanNode* xalanContextNode = ctx->docWrapper->mapNode(context_node);
        if (!xalanContextNode) {
            xalanContextNode = ctx->docWrapper;
        }

        // Get or compile XPath expression (cached)
        XPath* xpath = get_or_compile_xpath(doc_wrapper, ctx, xpath_str);

        // Create resolver for execution
        XalanElement* docElem = ctx->docWrapper->getDocumentElement();
        ElementPrefixResolverProxy resolver(docElem, *ctx->envSupport, *ctx->domSupport);

        // Reset execution context for clean state
        ctx->objectFactory->reset();

        // Execute XPath query
        const XObjectPtr result = xpath->execute(xalanContextNode, resolver, *ctx->executionContext);

        VALUE nodes_array = rb_ary_new();

        if (result.get() != 0) {
            // Check if result is a node set
            const NodeRefListBase& nodeList = result->nodeset();
            const NodeRefListBase::size_type length = nodeList.getLength();

            for (NodeRefListBase::size_type i = 0; i < length; ++i) {
                XalanNode* xalanNode = nodeList.item(i);
                if (xalanNode) {
                    // Map back to Xerces DOM node
                    const DOMNode* domNode = ctx->docWrapper->mapNode(xalanNode);
                    if (domNode) {
                        rb_ary_push(nodes_array, wrap_node(const_cast<DOMNode*>(domNode), doc_ref));
                    }
                }
            }
        }

        // Don't return xpath to factory - it's cached!

        NodeSetWrapper* wrapper = ALLOC(NodeSetWrapper);
        wrapper->nodes_array = nodes_array;
        return TypedData_Wrap_Struct(rb_cNodeSet, &nodeset_type, wrapper);

    } catch (const XalanXPathException& e) {
        CharStr msg(e.getMessage().c_str());
        rb_raise(rb_eRuntimeError, "XPath error: %s", msg.localForm());
    } catch (const XMLException& e) {
        CharStr message(e.getMessage());
        rb_raise(rb_eRuntimeError, "XML error: %s", message.localForm());
    } catch (...) {
        rb_raise(rb_eRuntimeError, "Unknown XPath error");
    }

    NodeSetWrapper* wrapper = ALLOC(NodeSetWrapper);
    wrapper->nodes_array = rb_ary_new();
    return TypedData_Wrap_Struct(rb_cNodeSet, &nodeset_type, wrapper);
}

// Optimized version that only returns the first matching node (for at_xpath)
// Avoids creating Ruby wrappers for all nodes when we only need one
static VALUE execute_xpath_with_xalan_first(DOMNode* context_node, const char* xpath_str, VALUE doc_ref) {
    // Validate XPath expression before execution
    validate_xpath_expression(xpath_str);

    ensure_xerces_initialized();

    try {
        // Get the document wrapper
        DocumentWrapper* doc_wrapper;
        TypedData_Get_Struct(doc_ref, DocumentWrapper, &document_type, doc_wrapper);

        DOMDocument* domDoc = doc_wrapper->doc;
        if (!domDoc) {
            return Qnil;
        }

        // Get or create cached Xalan context
        XalanContext* ctx = get_or_create_xalan_context(doc_wrapper);
        if (!ctx) {
            rb_raise(rb_eRuntimeError, "Failed to create Xalan context");
        }

        // Map the context node to Xalan
        XalanNode* xalanContextNode = ctx->docWrapper->mapNode(context_node);
        if (!xalanContextNode) {
            xalanContextNode = ctx->docWrapper;
        }

        // Get or compile XPath expression (cached)
        XPath* xpath = get_or_compile_xpath(doc_wrapper, ctx, xpath_str);

        // Create resolver for execution
        XalanElement* docElem = ctx->docWrapper->getDocumentElement();
        ElementPrefixResolverProxy resolver(docElem, *ctx->envSupport, *ctx->domSupport);

        // Reset execution context for clean state
        ctx->objectFactory->reset();

        // Execute XPath query
        const XObjectPtr result = xpath->execute(xalanContextNode, resolver, *ctx->executionContext);

        if (result.get() != 0) {
            // Check if result is a node set
            const NodeRefListBase& nodeList = result->nodeset();
            if (nodeList.getLength() > 0) {
                XalanNode* xalanNode = nodeList.item(0);
                if (xalanNode) {
                    // Map back to Xerces DOM node - only wrap the first one!
                    const DOMNode* domNode = ctx->docWrapper->mapNode(xalanNode);
                    if (domNode) {
                        return wrap_node(const_cast<DOMNode*>(domNode), doc_ref);
                    }
                }
            }
        }

        return Qnil;

    } catch (const XalanXPathException& e) {
        CharStr msg(e.getMessage().c_str());
        rb_raise(rb_eRuntimeError, "XPath error: %s", msg.localForm());
    } catch (const XMLException& e) {
        CharStr message(e.getMessage());
        rb_raise(rb_eRuntimeError, "XML error: %s", message.localForm());
    } catch (...) {
        rb_raise(rb_eRuntimeError, "Unknown XPath error");
    }

    return Qnil;
}
#endif

// document.xpath(path)
static VALUE document_xpath(VALUE self, VALUE path) {
    DocumentWrapper* doc_wrapper;
    TypedData_Get_Struct(self, DocumentWrapper, &document_type, doc_wrapper);

    if (!doc_wrapper->doc) {
        NodeSetWrapper* wrapper = ALLOC(NodeSetWrapper);
        wrapper->nodes_array = rb_ary_new();
        return TypedData_Wrap_Struct(rb_cNodeSet, &nodeset_type, wrapper);
    }

    Check_Type(path, T_STRING);
    const char* xpath_str = StringValueCStr(path);

    // Validate XPath expression before execution
    validate_xpath_expression(xpath_str);

#ifdef HAVE_XALAN
    // Use Xalan for full XPath 1.0 support
    DOMElement* root = doc_wrapper->doc->getDocumentElement();
    if (!root) {
        NodeSetWrapper* wrapper = ALLOC(NodeSetWrapper);
        wrapper->nodes_array = rb_ary_new();
        return TypedData_Wrap_Struct(rb_cNodeSet, &nodeset_type, wrapper);
    }
    return execute_xpath_with_xalan(root, xpath_str, self);
#else
    // Fall back to Xerces XPath subset
    try {
        DOMElement* root = doc_wrapper->doc->getDocumentElement();
        if (!root) {
            NodeSetWrapper* wrapper = ALLOC(NodeSetWrapper);
            wrapper->nodes_array = rb_ary_new();
            return TypedData_Wrap_Struct(rb_cNodeSet, &nodeset_type, wrapper);
        }

        DOMXPathNSResolver* resolver = doc_wrapper->doc->createNSResolver(root);
        XStr xpath_xstr(xpath_str);
        DOMXPathExpression* expression = doc_wrapper->doc->createExpression(
            xpath_xstr.unicodeForm(), resolver);

        DOMXPathResult* result = expression->evaluate(
            doc_wrapper->doc->getDocumentElement(),
            DOMXPathResult::ORDERED_NODE_SNAPSHOT_TYPE,
            NULL);

        VALUE nodes_array = rb_ary_new();
        XMLSize_t length = result->getSnapshotLength();

        for (XMLSize_t i = 0; i < length; i++) {
            result->snapshotItem(i);
            DOMNode* node = result->getNodeValue();
            if (node) {
                rb_ary_push(nodes_array, wrap_node(node, self));
            }
        }

        expression->release();
        resolver->release();
        result->release();

        NodeSetWrapper* wrapper = ALLOC(NodeSetWrapper);
        wrapper->nodes_array = nodes_array;
        return TypedData_Wrap_Struct(rb_cNodeSet, &nodeset_type, wrapper);

    } catch (const DOMXPathException& e) {
        CharStr message(e.getMessage());
        rb_raise(rb_eRuntimeError, "XPath error: %s", message.localForm());
    } catch (const DOMException& e) {
        CharStr message(e.getMessage());
        rb_raise(rb_eRuntimeError, "DOM error: %s", message.localForm());
    } catch (...) {
        rb_raise(rb_eRuntimeError, "Unknown XPath error");
    }

    NodeSetWrapper* wrapper = ALLOC(NodeSetWrapper);
    wrapper->nodes_array = rb_ary_new();
    return TypedData_Wrap_Struct(rb_cNodeSet, &nodeset_type, wrapper);
#endif
}

// document.at_xpath(path) - returns first matching node or nil
static VALUE document_at_xpath(VALUE self, VALUE path) {
    DocumentWrapper* doc_wrapper;
    TypedData_Get_Struct(self, DocumentWrapper, &document_type, doc_wrapper);

    if (!doc_wrapper->doc) {
        return Qnil;
    }

    Check_Type(path, T_STRING);
    const char* xpath_str = StringValueCStr(path);

    // Validate XPath expression before execution
    validate_xpath_expression(xpath_str);

#ifdef HAVE_XALAN
    // Use optimized first-only version
    DOMElement* root = doc_wrapper->doc->getDocumentElement();
    if (!root) {
        return Qnil;
    }
    return execute_xpath_with_xalan_first(root, xpath_str, self);
#else
    // Fall back to getting all results and returning first
    VALUE nodeset = document_xpath(self, path);
    NodeSetWrapper* wrapper;
    TypedData_Get_Struct(nodeset, NodeSetWrapper, &nodeset_type, wrapper);

    if (RARRAY_LEN(wrapper->nodes_array) == 0) {
        return Qnil;
    }

    return rb_ary_entry(wrapper->nodes_array, 0);
#endif
}

// document.css(selector) - Convert CSS to XPath and execute
static VALUE document_css(VALUE self, VALUE selector) {
    Check_Type(selector, T_STRING);
    const char* css_str = StringValueCStr(selector);

    // Convert CSS to XPath
    std::string xpath_str = css_to_xpath(css_str);

    // Call the xpath method with converted selector
    return document_xpath(self, rb_str_new2(xpath_str.c_str()));
}

// document.at_css(selector) - Returns first matching node
static VALUE document_at_css(VALUE self, VALUE selector) {
    Check_Type(selector, T_STRING);
    const char* css_str = StringValueCStr(selector);

    // Convert CSS to XPath
    std::string xpath_str = css_to_xpath(css_str);

#ifdef HAVE_XALAN
    DocumentWrapper* doc_wrapper;
    TypedData_Get_Struct(self, DocumentWrapper, &document_type, doc_wrapper);

    if (!doc_wrapper->doc) {
        return Qnil;
    }

    // Use optimized first-only version
    DOMElement* root = doc_wrapper->doc->getDocumentElement();
    if (!root) {
        return Qnil;
    }
    return execute_xpath_with_xalan_first(root, xpath_str.c_str(), self);
#else
    VALUE nodeset = document_css(self, selector);

    NodeSetWrapper* wrapper;
    TypedData_Get_Struct(nodeset, NodeSetWrapper, &nodeset_type, wrapper);

    if (RARRAY_LEN(wrapper->nodes_array) == 0) {
        return Qnil;
    }

    return rb_ary_entry(wrapper->nodes_array, 0);
#endif
}

// node.inspect - human-readable representation
static VALUE node_inspect(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return rb_str_new_cstr("#<RXerces::XML::Node (nil)>");
    }

    DOMNode::NodeType nodeType = wrapper->node->getNodeType();
    std::string result;

    // Add object ID
    char buf[32];
    snprintf(buf, sizeof(buf), "%016lx", (unsigned long)self);

    if (nodeType == DOMNode::ELEMENT_NODE) {
        result = "#<RXerces::XML::Element:0x";
        result += buf;
        result += " <";

        CharStr name(wrapper->node->getNodeName());
        result += name.localForm();

        // Add attributes
        DOMElement* element = dynamic_cast<DOMElement*>(wrapper->node);
        if (element) {
            DOMNamedNodeMap* attributes = element->getAttributes();
            if (attributes && attributes->getLength() > 0) {
                XMLSize_t attrLen = attributes->getLength();
                if (attrLen > 3) attrLen = 3;

                for (XMLSize_t i = 0; i < attrLen; i++) {
                    DOMNode* attr = attributes->item(i);
                    CharStr attrName(attr->getNodeName());
                    CharStr attrValue(attr->getNodeValue());
                    result += " ";
                    result += attrName.localForm();
                    result += "=\"";
                    result += attrValue.localForm();
                    result += "\"";
                }
                if (attributes->getLength() > 3) {
                    result += " ...";
                }
            }
        }

        result += ">";

        // Add truncated text content
        const XMLCh* textContent = wrapper->node->getTextContent();
        if (textContent && XMLString::stringLen(textContent) > 0) {
            CharStr text(textContent);
            std::string textStr = text.localForm();

            size_t start = textStr.find_first_not_of(" \t\n\r");
            if (start != std::string::npos) {
                size_t end = textStr.find_last_not_of(" \t\n\r");
                textStr = textStr.substr(start, end - start + 1);

                if (textStr.length() > 40) {
                    textStr = textStr.substr(0, 37) + "...";
                }

                result += "\"";
                result += textStr;
                result += "\"";
            }
        }

        result += ">";
    } else if (nodeType == DOMNode::TEXT_NODE) {
        result = "#<RXerces::XML::Text:0x";
        result += buf;
        result += " \"";

        const XMLCh* textContent = wrapper->node->getNodeValue();
        if (textContent) {
            CharStr text(textContent);
            std::string textStr = text.localForm();

            size_t start = textStr.find_first_not_of(" \t\n\r");
            if (start != std::string::npos) {
                size_t end = textStr.find_last_not_of(" \t\n\r");
                textStr = textStr.substr(start, end - start + 1);

                if (textStr.length() > 40) {
                    textStr = textStr.substr(0, 37) + "...";
                }

                result += textStr;
            }
        }

        result += "\">";
    } else {
        result = "#<RXerces::XML::Node:0x";
        result += buf;
        result += " ";
        CharStr name(wrapper->node->getNodeName());
        result += name.localForm();
        result += ">";
    }

    return rb_str_new_cstr(result.c_str());
}

// node.name
static VALUE node_name(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return Qnil;
    }

    const XMLCh* name = wrapper->node->getNodeName();
    CharStr utf8_name(name);

    return rb_str_new_cstr(utf8_name.localForm());
}

// node.namespace
static VALUE node_namespace(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return Qnil;
    }

    const XMLCh* namespaceURI = wrapper->node->getNamespaceURI();
    if (!namespaceURI || XMLString::stringLen(namespaceURI) == 0) {
        return Qnil;
    }

    CharStr utf8_namespace(namespaceURI);
    return rb_str_new_cstr(utf8_namespace.localForm());
}

// node.text / node.content
static VALUE node_text(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return rb_str_new_cstr("");
    }

    const XMLCh* content = wrapper->node->getTextContent();
    if (!content) {
        return rb_str_new_cstr("");
    }

    CharStr utf8_content(content);
    return rb_str_new_cstr(utf8_content.localForm());
}

// node.text = value
static VALUE node_text_set(VALUE self, VALUE text) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return Qnil;
    }

    Check_Type(text, T_STRING);
    const char* text_str = StringValueCStr(text);

    XStr text_xstr(text_str);
    wrapper->node->setTextContent(text_xstr.unicodeForm());

    return text;
}

// node[attribute_name]
static VALUE node_get_attribute(VALUE self, VALUE attr_name) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node || wrapper->node->getNodeType() != DOMNode::ELEMENT_NODE) {
        return Qnil;
    }

    Check_Type(attr_name, T_STRING);
    const char* attr_str = StringValueCStr(attr_name);

    DOMElement* element = dynamic_cast<DOMElement*>(wrapper->node);
    XStr attr_xstr(attr_str);
    const XMLCh* value = element->getAttribute(attr_xstr.unicodeForm());

    if (!value || XMLString::stringLen(value) == 0) {
        return Qnil;
    }

    CharStr utf8_value(value);
    return rb_str_new_cstr(utf8_value.localForm());
}

// node[attribute_name] = value
static VALUE node_set_attribute(VALUE self, VALUE attr_name, VALUE attr_value) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node || wrapper->node->getNodeType() != DOMNode::ELEMENT_NODE) {
        return Qnil;
    }

    Check_Type(attr_name, T_STRING);
    Check_Type(attr_value, T_STRING);

    const char* attr_str = StringValueCStr(attr_name);
    const char* value_str = StringValueCStr(attr_value);

    DOMElement* element = dynamic_cast<DOMElement*>(wrapper->node);
    XStr attr_xstr(attr_str);
    XStr value_xstr(value_str);
    element->setAttribute(attr_xstr.unicodeForm(), value_xstr.unicodeForm());

    return attr_value;
}

// node.has_attribute?(attribute_name)
static VALUE node_has_attribute_p(VALUE self, VALUE attr_name) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node || wrapper->node->getNodeType() != DOMNode::ELEMENT_NODE) {
        return Qfalse;
    }

    Check_Type(attr_name, T_STRING);
    const char* attr_str = StringValueCStr(attr_name);

    DOMElement* element = dynamic_cast<DOMElement*>(wrapper->node);
    XStr attr_xstr(attr_str);
    const XMLCh* value = element->getAttribute(attr_xstr.unicodeForm());

    if (!value || XMLString::stringLen(value) == 0) {
        return Qfalse;
    }

    return Qtrue;
}

// node.children
static VALUE node_children(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return rb_ary_new();
    }

    VALUE doc_ref = wrapper->doc_ref;

    DOMNodeList* child_nodes = wrapper->node->getChildNodes();
    XMLSize_t count = child_nodes->getLength();

    // Pre-size array for better performance
    VALUE children = rb_ary_new_capa((long)count);

    for (XMLSize_t i = 0; i < count; i++) {
        DOMNode* child = child_nodes->item(i);
        rb_ary_push(children, wrap_node(child, doc_ref));
    }

    return children;
}

// node.element_children - returns only element children (no text nodes)
static VALUE node_element_children(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return rb_ary_new();
    }

    VALUE doc_ref = wrapper->doc_ref;
    DOMNodeList* child_nodes = wrapper->node->getChildNodes();
    XMLSize_t count = child_nodes->getLength();

    // Pre-size array (may be smaller than count, but good estimate)
    VALUE children = rb_ary_new_capa((long)count);

    for (XMLSize_t i = 0; i < count; i++) {
        DOMNode* child = child_nodes->item(i);
        if (child->getNodeType() == DOMNode::ELEMENT_NODE) {
            rb_ary_push(children, wrap_node(child, doc_ref));
        }
    }

    return children;
}

// node.first_element_child - returns first element child
static VALUE node_first_element_child(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return Qnil;
    }

    VALUE doc_ref = wrapper->doc_ref;
    DOMNodeList* child_nodes = wrapper->node->getChildNodes();
    XMLSize_t count = child_nodes->getLength();

    for (XMLSize_t i = 0; i < count; i++) {
        DOMNode* child = child_nodes->item(i);
        if (child->getNodeType() == DOMNode::ELEMENT_NODE) {
            return wrap_node(child, doc_ref);
        }
    }

    return Qnil;
}

// node.last_element_child - returns last element child
static VALUE node_last_element_child(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return Qnil;
    }

    VALUE doc_ref = wrapper->doc_ref;
    DOMNodeList* child_nodes = wrapper->node->getChildNodes();
    XMLSize_t count = child_nodes->getLength();

    // Search backwards for last element
    for (XMLSize_t i = count; i > 0; i--) {
        DOMNode* child = child_nodes->item(i - 1);
        if (child->getNodeType() == DOMNode::ELEMENT_NODE) {
            return wrap_node(child, doc_ref);
        }
    }

    return Qnil;
}

// node.document - returns the document that owns this node
static VALUE node_document(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return Qnil;
    }

    return wrapper->doc_ref;
}

// node.parent
static VALUE node_parent(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return Qnil;
    }

    DOMNode* parent = wrapper->node->getParentNode();
    if (!parent) {
        return Qnil;
    }

    VALUE doc_ref = wrapper->doc_ref;
    return wrap_node(parent, doc_ref);
}

// node.ancestors(selector = nil) - returns an array of all ancestor nodes, optionally filtered by selector
static VALUE node_ancestors(int argc, VALUE* argv, VALUE self) {
    VALUE selector;
    rb_scan_args(argc, argv, "01", &selector);

    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    VALUE ancestors = rb_ary_new();

    if (!wrapper->node) {
        return ancestors;
    }

    VALUE doc_ref = wrapper->doc_ref;
    DOMNode* current = wrapper->node->getParentNode();

    // Walk up the tree, collecting all ancestors
    while (current) {
        // Stop at the document node (don't include it in ancestors)
        if (current->getNodeType() == DOMNode::DOCUMENT_NODE) {
            break;
        }
        rb_ary_push(ancestors, wrap_node(current, doc_ref));
        current = current->getParentNode();
    }

    // If selector is provided, filter the ancestors
    if (!NIL_P(selector)) {
        Check_Type(selector, T_STRING);
        const char* selector_str = StringValueCStr(selector);

        // Convert CSS to XPath if needed (css_to_xpath adds // prefix)
        std::string xpath_str = css_to_xpath(selector_str);

        // Get all matching nodes from the document
        VALUE all_matches = document_xpath(doc_ref, rb_str_new2(xpath_str.c_str()));

        NodeSetWrapper* matches_wrapper;
        TypedData_Get_Struct(all_matches, NodeSetWrapper, &nodeset_type, matches_wrapper);

        VALUE filtered = rb_ary_new();
        long ancestor_len = RARRAY_LEN(ancestors);
        long matches_len = RARRAY_LEN(matches_wrapper->nodes_array);

        // For each ancestor, check if it's in the matches
        for (long i = 0; i < ancestor_len; i++) {
            VALUE ancestor = rb_ary_entry(ancestors, i);

            NodeWrapper* ancestor_wrapper;
            TypedData_Get_Struct(ancestor, NodeWrapper, &node_type, ancestor_wrapper);

            // Check if this ancestor node is in the matches
            for (long j = 0; j < matches_len; j++) {
                VALUE match = rb_ary_entry(matches_wrapper->nodes_array, j);
                NodeWrapper* match_wrapper;
                TypedData_Get_Struct(match, NodeWrapper, &node_type, match_wrapper);

                // Compare the actual DOM nodes
                if (ancestor_wrapper->node == match_wrapper->node) {
                    rb_ary_push(filtered, ancestor);
                    break;
                }
            }
        }

        return filtered;
    }

    return ancestors;
}

// node.attributes - returns hash of all attributes (only for element nodes)
static VALUE node_attributes(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node || wrapper->node->getNodeType() != DOMNode::ELEMENT_NODE) {
        return rb_hash_new();
    }

    DOMElement* element = dynamic_cast<DOMElement*>(wrapper->node);
    DOMNamedNodeMap* attributes = element->getAttributes();

    if (!attributes) {
        return rb_hash_new();
    }

    VALUE hash = rb_hash_new();
    XMLSize_t length = attributes->getLength();

    for (XMLSize_t i = 0; i < length; i++) {
        DOMNode* attr = attributes->item(i);
        if (attr) {
            const XMLCh* name = attr->getNodeName();
            const XMLCh* value = attr->getNodeValue();

            CharStr attr_name(name);
            CharStr attr_value(value);

            rb_hash_aset(hash,
                        rb_str_new_cstr(attr_name.localForm()),
                        rb_str_new_cstr(attr_value.localForm()));
        }
    }

    return hash;
}

// node.attribute_nodes - returns array of attribute nodes (only for element nodes)
static VALUE node_attribute_nodes(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    VALUE nodes_array = rb_ary_new();

    if (!wrapper->node || wrapper->node->getNodeType() != DOMNode::ELEMENT_NODE) {
        return nodes_array;
    }

    DOMElement* element = dynamic_cast<DOMElement*>(wrapper->node);
    DOMNamedNodeMap* attributes = element->getAttributes();

    if (!attributes) {
        return nodes_array;
    }

    VALUE doc_ref = wrapper->doc_ref;
    XMLSize_t length = attributes->getLength();

    for (XMLSize_t i = 0; i < length; i++) {
        DOMNode* attr = attributes->item(i);
        if (attr) {
            rb_ary_push(nodes_array, wrap_node(attr, doc_ref));
        }
    }

    return nodes_array;
}

// node.next_sibling
static VALUE node_next_sibling(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return Qnil;
    }

    DOMNode* next = wrapper->node->getNextSibling();
    if (!next) {
        return Qnil;
    }

    VALUE doc_ref = wrapper->doc_ref;
    return wrap_node(next, doc_ref);
}

// node.previous_sibling
static VALUE node_previous_sibling(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return Qnil;
    }

    DOMNode* prev = wrapper->node->getPreviousSibling();
    if (!prev) {
        return Qnil;
    }

    VALUE doc_ref = wrapper->doc_ref;
    return wrap_node(prev, doc_ref);
}

// node.next_element - next sibling that is an element (skipping text nodes)
static VALUE node_next_element(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return Qnil;
    }

    VALUE doc_ref = wrapper->doc_ref;
    DOMNode* next = wrapper->node->getNextSibling();

    // Skip non-element nodes
    while (next && next->getNodeType() != DOMNode::ELEMENT_NODE) {
        next = next->getNextSibling();
    }

    if (!next) {
        return Qnil;
    }

    return wrap_node(next, doc_ref);
}

// node.previous_element - previous sibling that is an element (skipping text nodes)
static VALUE node_previous_element(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return Qnil;
    }

    VALUE doc_ref = wrapper->doc_ref;
    DOMNode* prev = wrapper->node->getPreviousSibling();

    // Skip non-element nodes
    while (prev && prev->getNodeType() != DOMNode::ELEMENT_NODE) {
        prev = prev->getPreviousSibling();
    }

    if (!prev) {
        return Qnil;
    }

    return wrap_node(prev, doc_ref);
}

// node.add_child(node_or_string) - adds a child node
static VALUE node_add_child(VALUE self, VALUE child) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        rb_raise(rb_eRuntimeError, "Cannot add child to null node");
    }

    DOMDocument* doc = wrapper->node->getOwnerDocument();
    if (!doc) {
        rb_raise(rb_eRuntimeError, "Node has no owner document");
    }

    DOMNode* child_node = NULL;
    VALUE doc_ref = wrapper->doc_ref;  // Keep track of the Ruby document reference

    // Check if child is a string or a node
    if (TYPE(child) == T_STRING) {
        // Create a text node from the string
        const char* text_str = StringValueCStr(child);
        XMLCh* text_content = XMLString::transcode(text_str);
        child_node = doc->createTextNode(text_content);
        XMLString::release(&text_content);
    } else {
        // Assume it's a Node object
        NodeWrapper* child_wrapper;
        if (rb_obj_is_kind_of(child, rb_cNode)) {
            TypedData_Get_Struct(child, NodeWrapper, &node_type, child_wrapper);
            DOMNode* original_child = child_wrapper->node;

            // Check if child belongs to a different document
            DOMDocument* child_doc = original_child->getOwnerDocument();
            if (child_doc && child_doc != doc) {
                // Automatically import the node from the other document
                // The second parameter 'true' means deep copy (include all descendants)
                try {
                    child_node = doc->importNode(original_child, true);

                    // Update the child wrapper to point to the imported node
                    // and the new document reference
                    child_wrapper->node = child_node;
                    child_wrapper->doc_ref = doc_ref;
                } catch (const DOMException& e) {
                    CharStr message(e.getMessage());
                    rb_raise(rb_eRuntimeError, "Failed to import node from different document: %s",
                             message.localForm());
                }
            } else {
                child_node = original_child;
            }
        } else {
            rb_raise(rb_eTypeError, "Argument must be a String or Node");
        }
    }

    if (!child_node) {
        rb_raise(rb_eRuntimeError, "Failed to create child node");
    }

    try {
        // appendChild will automatically detach the node from its current parent if it has one
        wrapper->node->appendChild(child_node);
    } catch (const DOMException& e) {
        char* message = XMLString::transcode(e.getMessage());
        VALUE rb_error = rb_str_new_cstr(message);
        XMLString::release(&message);

        // Provide more context for common errors
        unsigned short code = e.code;
        if (code == DOMException::WRONG_DOCUMENT_ERR) {
            rb_raise(rb_eRuntimeError, "Node belongs to a different document: %s", StringValueCStr(rb_error));
        } else if (code == DOMException::HIERARCHY_REQUEST_ERR) {
            rb_raise(rb_eRuntimeError, "Invalid hierarchy: cannot add this node as a child: %s", StringValueCStr(rb_error));
        } else if (code == DOMException::NO_MODIFICATION_ALLOWED_ERR) {
            rb_raise(rb_eRuntimeError, "Node is read-only: %s", StringValueCStr(rb_error));
        } else {
            rb_raise(rb_eRuntimeError, "Failed to add child: %s", StringValueCStr(rb_error));
        }
    }

    return child;
}

// node.remove / node.unlink - removes node from its parent
static VALUE node_remove(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        rb_raise(rb_eRuntimeError, "Cannot remove null node");
    }

    DOMNode* parent = wrapper->node->getParentNode();
    if (!parent) {
        rb_raise(rb_eRuntimeError, "Node has no parent to remove from");
    }

    try {
        parent->removeChild(wrapper->node);
    } catch (const DOMException& e) {
        char* message = XMLString::transcode(e.getMessage());
        VALUE rb_error = rb_str_new_cstr(message);
        XMLString::release(&message);
        rb_raise(rb_eRuntimeError, "Failed to remove node: %s", StringValueCStr(rb_error));
    }

    return self;
}

// node.inner_html / node.inner_xml - returns XML content of children
static VALUE node_inner_html(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return rb_str_new_cstr("");
    }

    try {
        XStr ls_name("LS");
        DOMImplementation* impl = DOMImplementationRegistry::getDOMImplementation(ls_name.unicodeForm());
        DOMLSSerializer* serializer = ((DOMImplementationLS*)impl)->createLSSerializer();

        // Build a string by serializing each child
        std::string result;
        DOMNodeList* children = wrapper->node->getChildNodes();
        XMLSize_t count = children->getLength();

        for (XMLSize_t i = 0; i < count; i++) {
            DOMNode* child = children->item(i);
            XMLCh* xml_str = serializer->writeToString(child);
            CharStr utf8_str(xml_str);
            result += utf8_str.localForm();
            XMLString::release(&xml_str);
        }

        serializer->release();
        return rb_str_new_cstr(result.c_str());
    } catch (const DOMException& e) {
        char* message = XMLString::transcode(e.getMessage());
        VALUE rb_error = rb_str_new_cstr(message);
        XMLString::release(&message);
        rb_raise(rb_eRuntimeError, "Failed to serialize inner content: %s", StringValueCStr(rb_error));
    } catch (...) {
        rb_raise(rb_eRuntimeError, "Failed to serialize inner content");
    }

    return rb_str_new_cstr("");
}

// node.path - returns XPath to the node
static VALUE node_path(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return rb_str_new_cstr("");
    }

    std::string path = "";
    DOMNode* current = wrapper->node;

    // Build path from current node to root
    while (current && current->getNodeType() != DOMNode::DOCUMENT_NODE) {
        std::string segment = "";

        if (current->getNodeType() == DOMNode::ELEMENT_NODE) {
            CharStr name(current->getNodeName());
            segment = std::string(name.localForm());

            // Count position among siblings with same name
            int position = 1;
            DOMNode* sibling = current->getPreviousSibling();
            while (sibling) {
                if (sibling->getNodeType() == DOMNode::ELEMENT_NODE &&
                    XMLString::equals(sibling->getNodeName(), current->getNodeName())) {
                    position++;
                }
                sibling = sibling->getPreviousSibling();
            }

            // Add position predicate
            segment += "[" + std::to_string(position) + "]";
            path = "/" + segment + path;
        } else if (current->getNodeType() == DOMNode::TEXT_NODE) {
            // Count position among text node siblings
            int position = 1;
            DOMNode* sibling = current->getPreviousSibling();
            while (sibling) {
                if (sibling->getNodeType() == DOMNode::TEXT_NODE) {
                    position++;
                }
                sibling = sibling->getPreviousSibling();
            }
            path = "/text()[" + std::to_string(position) + "]" + path;
        }

        current = current->getParentNode();
    }

    return rb_str_new_cstr(path.c_str());
}

// node.blank? - returns true if node has no meaningful content
static VALUE node_blank_p(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    if (!wrapper->node) {
        return Qtrue;
    }

    // Text nodes are blank if they contain only whitespace
    if (wrapper->node->getNodeType() == DOMNode::TEXT_NODE) {
        const XMLCh* text_content = wrapper->node->getNodeValue();
        if (!text_content) {
            return Qtrue;
        }

        // Check if text contains only whitespace
        CharStr utf8_text(text_content);
        const char* str = utf8_text.localForm();
        while (*str) {
            if (!isspace((unsigned char)*str)) {
                return Qfalse;
            }
            str++;
        }
        return Qtrue;
    }

    // Element nodes are blank if they have no child elements and no non-blank text
    if (wrapper->node->getNodeType() == DOMNode::ELEMENT_NODE) {
        DOMNodeList* children = wrapper->node->getChildNodes();
        XMLSize_t count = children->getLength();

        if (count == 0) {
            return Qtrue;
        }

        // Check if all children are blank text nodes
        for (XMLSize_t i = 0; i < count; i++) {
            DOMNode* child = children->item(i);

            // If there's an element child, not blank
            if (child->getNodeType() == DOMNode::ELEMENT_NODE) {
                return Qfalse;
            }

            // If there's a non-whitespace text node, not blank
            if (child->getNodeType() == DOMNode::TEXT_NODE) {
                const XMLCh* text_content = child->getNodeValue();
                if (text_content) {
                    CharStr utf8_text(text_content);
                    const char* str = utf8_text.localForm();
                    while (*str) {
                        if (!isspace((unsigned char)*str)) {
                            return Qfalse;
                        }
                        str++;
                    }
                }
            }
        }

        return Qtrue;
    }

    // Other node types are considered blank
    return Qtrue;
}

// node.xpath(path)
static VALUE node_xpath(VALUE self, VALUE path) {
    NodeWrapper* node_wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, node_wrapper);

    if (!node_wrapper->node) {
        NodeSetWrapper* wrapper = ALLOC(NodeSetWrapper);
        wrapper->nodes_array = rb_ary_new();
        return TypedData_Wrap_Struct(rb_cNodeSet, &nodeset_type, wrapper);
    }

    Check_Type(path, T_STRING);
    const char* xpath_str = StringValueCStr(path);
    VALUE doc_ref = node_wrapper->doc_ref;

    // Validate XPath expression before execution
    validate_xpath_expression(xpath_str);

#ifdef HAVE_XALAN
    // Use Xalan for full XPath 1.0 support
    return execute_xpath_with_xalan(node_wrapper->node, xpath_str, doc_ref);
#else
    // Fall back to Xerces XPath subset
    try {
        DOMDocument* doc = node_wrapper->node->getOwnerDocument();
        if (!doc) {
            NodeSetWrapper* wrapper = ALLOC(NodeSetWrapper);
            wrapper->nodes_array = rb_ary_new();
            return TypedData_Wrap_Struct(rb_cNodeSet, &nodeset_type, wrapper);
        }

        DOMXPathNSResolver* resolver = doc->createNSResolver(node_wrapper->node);
        XStr xpath_xstr(xpath_str);
        DOMXPathExpression* expression = doc->createExpression(
            xpath_xstr.unicodeForm(), resolver);

        DOMXPathResult* result = expression->evaluate(
            node_wrapper->node,
            DOMXPathResult::ORDERED_NODE_SNAPSHOT_TYPE,
            NULL);

        VALUE nodes_array = rb_ary_new();
        XMLSize_t length = result->getSnapshotLength();

        for (XMLSize_t i = 0; i < length; i++) {
            result->snapshotItem(i);
            DOMNode* node = result->getNodeValue();
            if (node) {
                rb_ary_push(nodes_array, wrap_node(node, doc_ref));
            }
        }

        expression->release();
        resolver->release();
        result->release();

        NodeSetWrapper* wrapper = ALLOC(NodeSetWrapper);
        wrapper->nodes_array = nodes_array;
        return TypedData_Wrap_Struct(rb_cNodeSet, &nodeset_type, wrapper);

    } catch (const DOMXPathException& e) {
        CharStr message(e.getMessage());
        rb_raise(rb_eRuntimeError, "XPath error: %s", message.localForm());
    } catch (const DOMException& e) {
        CharStr message(e.getMessage());
        rb_raise(rb_eRuntimeError, "DOM error: %s", message.localForm());
    } catch (...) {
        rb_raise(rb_eRuntimeError, "Unknown XPath error");
    }

    NodeSetWrapper* wrapper = ALLOC(NodeSetWrapper);
    wrapper->nodes_array = rb_ary_new();
    return TypedData_Wrap_Struct(rb_cNodeSet, &nodeset_type, wrapper);
#endif
}

// node.at_xpath(path) - returns first matching node or nil
static VALUE node_at_xpath(VALUE self, VALUE path) {
    NodeWrapper* node_wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, node_wrapper);

    if (!node_wrapper->node) {
        return Qnil;
    }

    Check_Type(path, T_STRING);
    const char* xpath_str = StringValueCStr(path);
    VALUE doc_ref = node_wrapper->doc_ref;

    // Validate XPath expression before execution
    validate_xpath_expression(xpath_str);

#ifdef HAVE_XALAN
    // Use optimized first-only version
    return execute_xpath_with_xalan_first(node_wrapper->node, xpath_str, doc_ref);
#else
    // Fall back to getting all results and returning first
    VALUE nodeset = node_xpath(self, path);
    NodeSetWrapper* wrapper;
    TypedData_Get_Struct(nodeset, NodeSetWrapper, &nodeset_type, wrapper);

    if (RARRAY_LEN(wrapper->nodes_array) == 0) {
        return Qnil;
    }

    return rb_ary_entry(wrapper->nodes_array, 0);
#endif
}

// node.at_css(selector) - returns first matching node or nil
static VALUE node_at_css(VALUE self, VALUE selector) {
    Check_Type(selector, T_STRING);
    const char* css_str = StringValueCStr(selector);

    // Convert CSS to XPath
    std::string xpath_str = css_to_xpath(css_str);

#ifdef HAVE_XALAN
    NodeWrapper* node_wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, node_wrapper);

    if (!node_wrapper->node) {
        return Qnil;
    }

    VALUE doc_ref = node_wrapper->doc_ref;

    // Use optimized first-only version
    return execute_xpath_with_xalan_first(node_wrapper->node, xpath_str.c_str(), doc_ref);
#else
    VALUE nodeset = node_css(self, selector);
    NodeSetWrapper* wrapper;
    TypedData_Get_Struct(nodeset, NodeSetWrapper, &nodeset_type, wrapper);

    if (RARRAY_LEN(wrapper->nodes_array) == 0) {
        return Qnil;
    }

    return rb_ary_entry(wrapper->nodes_array, 0);
#endif
}

// Helper function to convert basic CSS selectors to XPath
// Supports common patterns like: tag, .class, #id, tag.class, tag#id, [attr], [attr=value]
static std::string css_to_xpath(const char* css) {
    std::string selector(css);

    // Trim whitespace
    size_t start = selector.find_first_not_of(" \t\n\r");
    size_t end = selector.find_last_not_of(" \t\n\r");
    if (start == std::string::npos) return "//*";
    selector = selector.substr(start, end - start + 1);

    std::string result = "//";
    std::string current_element = "*";
    bool has_element = false;
    bool in_brackets = false;

    for (size_t i = 0; i < selector.length(); i++) {
        char c = selector[i];

        if (c == '[') in_brackets = true;
        if (c == ']') in_brackets = false;

        // Handle spaces (descendant combinator) outside of attribute selectors
        if (c == ' ' && !in_brackets) {
            // Flush current element
            if (!has_element && current_element != "*") {
                result += current_element;
            }
            // Skip multiple spaces
            while (i + 1 < selector.length() && selector[i + 1] == ' ') i++;
            result += "//";
            current_element = "*";
            has_element = false;
            continue;
        }

        // Handle child combinator
        if (c == '>' && !in_brackets) {
            // Flush current element
            if (!has_element && current_element != "*") {
                result += current_element;
            }
            // Remove any trailing slashes and spaces
            while (!result.empty() && (result.back() == ' ' || result.back() == '/')) {
                if (result.back() == '/') {
                    result.pop_back();
                    break;
                }
                result.pop_back();
            }
            result += "/";
            // Skip spaces after >
            while (i + 1 < selector.length() && selector[i + 1] == ' ') i++;
            current_element = "*";
            has_element = false;
            continue;
        }

        // Handle ID selector
        if (c == '#' && !in_brackets) {
            if (!has_element) {
                result += "*";
                has_element = true;
            } else if (current_element != "*") {
                result += current_element;
                current_element = "*";
                has_element = true;
            }
            result += "[@id='";
            i++;
            while (i < selector.length() && selector[i] != ' ' && selector[i] != '.' &&
                   selector[i] != '[' && selector[i] != '>' && selector[i] != '+' && selector[i] != '~') {
                result += selector[i++];
            }
            result += "']";
            i--;
            continue;
        }

        // Handle class selector
        if (c == '.' && !in_brackets) {
            if (!has_element) {
                result += "*";
                has_element = true;
            } else if (current_element != "*") {
                result += current_element;
                current_element = "*";
                has_element = true;
            }
            result += "[contains(concat(' ', @class, ' '), ' ";
            i++;
            while (i < selector.length() && selector[i] != ' ' && selector[i] != '.' &&
                   selector[i] != '[' && selector[i] != '>' && selector[i] != '+' && selector[i] != '~' && selector[i] != '#') {
                result += selector[i++];
            }
            result += " ')]";
            i--;
            continue;
        }

        // Handle attribute selectors
        if (c == '[') {
            if (!has_element && current_element != "*") {
                result += current_element;
                has_element = true;
            }
            result += "[@";
            i++;
            // Get attribute name
            while (i < selector.length() && selector[i] != ']' && selector[i] != '=' &&
                   selector[i] != '!' && selector[i] != '~' && selector[i] != '^' && selector[i] != '$' && selector[i] != '*') {
                result += selector[i++];
            }

            if (i < selector.length() && selector[i] == '=') {
                result += "='";
                i++;
                // Skip quotes if present
                if (i < selector.length() && (selector[i] == '"' || selector[i] == '\'')) {
                    char quote = selector[i++];
                    while (i < selector.length() && selector[i] != quote) {
                        result += selector[i++];
                    }
                    if (i < selector.length()) i++; // Skip closing quote
                } else {
                    // No quotes, read until ]
                    while (i < selector.length() && selector[i] != ']') {
                        result += selector[i++];
                    }
                }
                result += "'";
            }

            // Skip to closing bracket
            while (i < selector.length() && selector[i] != ']') i++;
            result += ']';
            continue;
        }

        // Regular character - part of element name
        if (c != ' ' && c != '>' && c != '.' && c != '#' && c != '[' && !has_element) {
            if (current_element == "*") {
                current_element = "";
            }
            current_element += c;
        }
    }

    // Flush any remaining element name
    if (!has_element && current_element != "*") {
        result += current_element;
    }

    return result;
}

// node.css(selector) - Convert CSS to XPath and execute
static VALUE node_css(VALUE self, VALUE selector) {
    Check_Type(selector, T_STRING);
    const char* css_str = StringValueCStr(selector);

    // Convert CSS to XPath
    std::string xpath_str = css_to_xpath(css_str);

    // Call the xpath method with converted selector
    return node_xpath(self, rb_str_new2(xpath_str.c_str()));
}

// nodeset.length / nodeset.size
static VALUE nodeset_length(VALUE self) {
    NodeSetWrapper* wrapper;
    TypedData_Get_Struct(self, NodeSetWrapper, &nodeset_type, wrapper);

    return LONG2NUM(RARRAY_LEN(wrapper->nodes_array));
}

// nodeset[index]
static VALUE nodeset_at(VALUE self, VALUE index) {
    NodeSetWrapper* wrapper;
    TypedData_Get_Struct(self, NodeSetWrapper, &nodeset_type, wrapper);

    return rb_ary_entry(wrapper->nodes_array, NUM2LONG(index));
}

// nodeset.each
static VALUE nodeset_each(VALUE self) {
    NodeSetWrapper* wrapper;
    TypedData_Get_Struct(self, NodeSetWrapper, &nodeset_type, wrapper);

    if (!rb_block_given_p()) {
        return rb_funcall(wrapper->nodes_array, rb_intern("each"), 0);
    }

    long len = RARRAY_LEN(wrapper->nodes_array);
    for (long i = 0; i < len; i++) {
        rb_yield(rb_ary_entry(wrapper->nodes_array, i));
    }

    return self;
}

// nodeset.to_a
static VALUE nodeset_to_a(VALUE self) {
    NodeSetWrapper* wrapper;
    TypedData_Get_Struct(self, NodeSetWrapper, &nodeset_type, wrapper);

    return rb_ary_dup(wrapper->nodes_array);
}

// nodeset.first - returns first node or nil
static VALUE nodeset_first(VALUE self) {
    NodeSetWrapper* wrapper;
    TypedData_Get_Struct(self, NodeSetWrapper, &nodeset_type, wrapper);

    if (RARRAY_LEN(wrapper->nodes_array) == 0) {
        return Qnil;
    }

    return rb_ary_entry(wrapper->nodes_array, 0);
}

// nodeset.last - returns last node or nil
static VALUE nodeset_last(VALUE self) {
    NodeSetWrapper* wrapper;
    TypedData_Get_Struct(self, NodeSetWrapper, &nodeset_type, wrapper);

    long len = RARRAY_LEN(wrapper->nodes_array);
    if (len == 0) {
        return Qnil;
    }

    return rb_ary_entry(wrapper->nodes_array, len - 1);
}

// nodeset.empty? - returns true if nodeset is empty
static VALUE nodeset_empty_p(VALUE self) {
    NodeSetWrapper* wrapper;
    TypedData_Get_Struct(self, NodeSetWrapper, &nodeset_type, wrapper);

    return RARRAY_LEN(wrapper->nodes_array) == 0 ? Qtrue : Qfalse;
}

// nodeset.inner_html - returns concatenated inner_html of all nodes
static VALUE nodeset_inner_html(VALUE self) {
    NodeSetWrapper* wrapper;
    TypedData_Get_Struct(self, NodeSetWrapper, &nodeset_type, wrapper);

    std::string result;
    long len = RARRAY_LEN(wrapper->nodes_array);

    for (long i = 0; i < len; i++) {
        VALUE node = rb_ary_entry(wrapper->nodes_array, i);
        VALUE inner_html = rb_funcall(node, rb_intern("inner_html"), 0);
        result += StringValueCStr(inner_html);
    }

    return rb_str_new_cstr(result.c_str());
}

// nodeset.text - returns concatenated text content of all nodes
static VALUE nodeset_text(VALUE self) {
    NodeSetWrapper* wrapper;
    TypedData_Get_Struct(self, NodeSetWrapper, &nodeset_type, wrapper);

    std::string result;
    long len = RARRAY_LEN(wrapper->nodes_array);

    for (long i = 0; i < len; i++) {
        VALUE node = rb_ary_entry(wrapper->nodes_array, i);
        NodeWrapper* node_wrapper;
        TypedData_Get_Struct(node, NodeWrapper, &node_type, node_wrapper);

        if (node_wrapper->node) {
            const XMLCh* content = node_wrapper->node->getTextContent();
            if (content) {
                CharStr utf8_content(content);
                result += utf8_content.localForm();
            }
        }
    }

    return rb_str_new_cstr(result.c_str());
}

// nodeset.inspect / nodeset.to_s - human-readable representation
// Helper function to safely truncate UTF-8 strings using Ruby's built-in UTF-8 handling
// Ruby's rb_str_substr operates on CHARACTER positions, not byte positions
static std::string safe_truncate_utf8(const std::string& str, long max_chars) {
    if (str.empty()) {
        return str;
    }

    // Create a Ruby string with UTF-8 encoding
    VALUE rb_str = rb_enc_str_new(str.c_str(), str.length(), rb_utf8_encoding());

    // Get the character length (not byte length)
    long char_len = RSTRING_LEN(rb_str);

    if (char_len <= max_chars) {
        return str;
    }

    // Use Ruby's rb_str_substr which correctly handles multi-byte characters
    // Parameters: string, start position (in characters), length (in characters)
    VALUE truncated = rb_str_substr(rb_str, 0, max_chars);

    // Convert back to C++ string
    return std::string(RSTRING_PTR(truncated), RSTRING_LEN(truncated));
}

static VALUE nodeset_inspect(VALUE self) {
    NodeSetWrapper* wrapper;
    TypedData_Get_Struct(self, NodeSetWrapper, &nodeset_type, wrapper);

    long len = RARRAY_LEN(wrapper->nodes_array);
    std::string result = "#<RXerces::XML::NodeSet:0x";

    // Add object ID
    char buf[32];
    snprintf(buf, sizeof(buf), "%016lx", (unsigned long)self);
    result += buf;
    result += " [";

    for (long i = 0; i < len; i++) {
        if (i > 0) result += ", ";

        VALUE node = rb_ary_entry(wrapper->nodes_array, i);
        NodeWrapper* node_wrapper;
        TypedData_Get_Struct(node, NodeWrapper, &node_type, node_wrapper);

        if (!node_wrapper->node) {
            result += "nil";
            continue;
        }

        DOMNode::NodeType nodeType = node_wrapper->node->getNodeType();

        if (nodeType == DOMNode::ELEMENT_NODE) {
            // For elements, show: <tag attr="value">content</tag>
            CharStr name(node_wrapper->node->getNodeName());
            result += "<";
            result += name.localForm();

            // Add first few attributes if present
            DOMElement* element = dynamic_cast<DOMElement*>(node_wrapper->node);
            if (element) {
                DOMNamedNodeMap* attributes = element->getAttributes();
                if (attributes && attributes->getLength() > 0) {
                    XMLSize_t attrLen = attributes->getLength();
                    if (attrLen > 3) attrLen = 3; // Limit to first 3 attributes

                    for (XMLSize_t j = 0; j < attrLen; j++) {
                        DOMNode* attr = attributes->item(j);
                        CharStr attrName(attr->getNodeName());
                        CharStr attrValue(attr->getNodeValue());
                        result += " ";
                        result += attrName.localForm();
                        result += "=\"";
                        result += attrValue.localForm();
                        result += "\"";
                    }
                    if (attributes->getLength() > 3) {
                        result += " ...";
                    }
                }
            }

            // Show truncated text content
            const XMLCh* textContent = node_wrapper->node->getTextContent();
            if (textContent && XMLString::stringLen(textContent) > 0) {
                CharStr text(textContent);
                std::string textStr = text.localForm();

                // Trim whitespace and truncate
                size_t start = textStr.find_first_not_of(" \t\n\r");
                if (start != std::string::npos) {
                    size_t end = textStr.find_last_not_of(" \t\n\r");
                    textStr = textStr.substr(start, end - start + 1);

                    if (textStr.length() > 30) {
                        textStr = safe_truncate_utf8(textStr, 27) + "...";
                    }

                    result += ">";
                    result += textStr;
                    result += "</";
                    result += name.localForm();
                    result += ">";
                } else {
                    result += ">";
                }
            } else {
                result += ">";
            }
        } else if (nodeType == DOMNode::TEXT_NODE) {
            // For text nodes, show: text("content")
            const XMLCh* textContent = node_wrapper->node->getNodeValue();
            if (textContent) {
                CharStr text(textContent);
                std::string textStr = text.localForm();

                // Trim and truncate
                size_t start = textStr.find_first_not_of(" \t\n\r");
                if (start != std::string::npos) {
                    size_t end = textStr.find_last_not_of(" \t\n\r");
                    textStr = textStr.substr(start, end - start + 1);

                    if (textStr.length() > 30) {
                        textStr = safe_truncate_utf8(textStr, 27) + "...";
                    }

                    result += "text(\"";
                    result += textStr;
                    result += "\")";
                } else {
                    result += "text()";
                }
            } else {
                result += "text()";
            }
        } else {
            // For other nodes, just show the type
            CharStr name(node_wrapper->node->getNodeName());
            result += "#<";
            result += name.localForm();
            result += ">";
        }
    }

    result += "]>";
    VALUE rb_result = rb_str_new_cstr(result.c_str());
    // Ensure the string is marked as UTF-8 encoded
    rb_enc_associate(rb_result, rb_utf8_encoding());
    return rb_result;
}

// Schema.from_document(schema_doc) or Schema.from_string(xsd_string)
static VALUE schema_from_document(int argc, VALUE* argv, VALUE klass) {
    VALUE schema_source;
    rb_scan_args(argc, argv, "1", &schema_source);

    ensure_xerces_initialized();

    try {
        SchemaWrapper* wrapper = ALLOC(SchemaWrapper);
        wrapper->schemaContent = new std::string();

        // Convert schema source to string
        std::string xsd_content;
        if (rb_obj_is_kind_of(schema_source, rb_cString)) {
            xsd_content = std::string(RSTRING_PTR(schema_source), RSTRING_LEN(schema_source));
        } else {
            // Assume it's a Document, call to_s
            VALUE str = rb_funcall(schema_source, rb_intern("to_s"), 0);
            xsd_content = std::string(RSTRING_PTR(str), RSTRING_LEN(str));
        }

        // Store the schema content
        *wrapper->schemaContent = xsd_content;

        // Validate that it's valid XML by trying to parse it
        XercesDOMParser* schemaParser = new XercesDOMParser();
        schemaParser->setValidationScheme(XercesDOMParser::Val_Never);
        schemaParser->setDoNamespaces(true);

        // Parse the schema using MemBufInputSource
        MemBufInputSource schemaInput(
            (const XMLByte*)xsd_content.c_str(),
            xsd_content.length(),
            "schema"
        );

        try {
            schemaParser->parse(schemaInput);
        } catch (const XMLException& e) {
            delete schemaParser;
            delete wrapper->schemaContent;
            xfree(wrapper);
            CharStr message(e.getMessage());
            rb_raise(rb_eRuntimeError, "Schema parsing failed: %s", message.localForm());
        } catch (const SAXException& e) {
            delete schemaParser;
            delete wrapper->schemaContent;
            xfree(wrapper);
            CharStr message(e.getMessage());
            rb_raise(rb_eRuntimeError, "Schema parsing failed: %s", message.localForm());
        } catch (...) {
            delete schemaParser;
            delete wrapper->schemaContent;
            xfree(wrapper);
            rb_raise(rb_eRuntimeError, "Schema parsing failed: Invalid XML");
        }

        delete schemaParser;

        VALUE rb_schema = TypedData_Wrap_Struct(klass, &schema_type, wrapper);
        return rb_schema;

    } catch (const XMLException& e) {
        char* message = XMLString::transcode(e.getMessage());
        VALUE rb_error = rb_str_new_cstr(message);
        XMLString::release(&message);
        rb_raise(rb_eRuntimeError, "XMLException: %s", StringValueCStr(rb_error));
    } catch (const DOMException& e) {
        char* message = XMLString::transcode(e.getMessage());
        VALUE rb_error = rb_str_new_cstr(message);
        XMLString::release(&message);
        rb_raise(rb_eRuntimeError, "DOMException: %s", StringValueCStr(rb_error));
    } catch (...) {
        rb_raise(rb_eRuntimeError, "Unknown exception during schema parsing");
    }

    return Qnil;
}

// document.validate(schema) - returns array of error messages (empty if valid)
static VALUE document_validate(VALUE self, VALUE rb_schema) {
    DocumentWrapper* doc_wrapper;
    TypedData_Get_Struct(self, DocumentWrapper, &document_type, doc_wrapper);

    SchemaWrapper* schema_wrapper;
    TypedData_Get_Struct(rb_schema, SchemaWrapper, &schema_type, schema_wrapper);

    try {
        // Serialize the document to UTF-8 for validation
        DOMImplementation* impl = DOMImplementationRegistry::getDOMImplementation(XMLString::transcode("LS"));
        DOMLSSerializer* serializer = ((DOMImplementationLS*)impl)->createLSSerializer();

        // Use a MemBufFormatTarget to get UTF-8 encoded output
        MemBufFormatTarget target;
        DOMLSOutput* output = ((DOMImplementationLS*)impl)->createLSOutput();
        output->setByteStream(&target);

        serializer->write(doc_wrapper->doc, output);

        // Get the UTF-8 content
        std::string xml_content((const char*)target.getRawBuffer(), target.getLen());

        output->release();
        serializer->release();

        // Create a validating parser
        XercesDOMParser* validator = new XercesDOMParser();
        validator->setValidationScheme(XercesDOMParser::Val_Always);
        validator->setDoNamespaces(true);
        validator->setDoSchema(true);
        validator->setValidationSchemaFullChecking(true);

        ValidationErrorHandler errorHandler;
        validator->setErrorHandler(&errorHandler);

        // Create a combined input with both the schema and the document
        // First, we need to add schema location to the document
        std::string schema_location = "http://example.com/schema";

        // Create memory buffers for both schema and document
        MemBufInputSource schemaSource(
            (const XMLByte*)schema_wrapper->schemaContent->c_str(),
            schema_wrapper->schemaContent->length(),
            "schema.xsd"
        );

        // Load the schema grammar
        try {
            validator->loadGrammar(schemaSource, Grammar::SchemaGrammarType, true);
            validator->setExternalNoNamespaceSchemaLocation("schema.xsd");
            validator->useCachedGrammarInParse(true);
        } catch (const XMLException& e) {
            CharStr message(e.getMessage());
            errorHandler.errors.push_back(std::string("Warning: Schema grammar could not be loaded: ") + message.localForm());
        } catch (const SAXException& e) {
            CharStr message(e.getMessage());
            errorHandler.errors.push_back(std::string("Warning: Schema grammar could not be loaded: ") + message.localForm());
        } catch (...) {
            // If grammar loading fails, just note it
            errorHandler.errors.push_back("Warning: Schema grammar could not be loaded");
        }

        // Now parse and validate the document
        MemBufInputSource docSource(
            (const XMLByte*)xml_content.c_str(),
            xml_content.length(),
            "document.xml"
        );

        try {
            validator->parse(docSource);
        } catch (const XMLException& e) {
            char* message = XMLString::transcode(e.getMessage());
            errorHandler.errors.push_back(std::string("XMLException: ") + message);
            XMLString::release(&message);
        } catch (const DOMException& e) {
            char* message = XMLString::transcode(e.getMessage());
            errorHandler.errors.push_back(std::string("DOMException: ") + message);
            XMLString::release(&message);
        } catch (...) {
            errorHandler.errors.push_back("Unknown parsing exception");
        }

        delete validator;

        // Return array of error messages
        VALUE errors_array = rb_ary_new();
        for (const auto& err : errorHandler.errors) {
            rb_ary_push(errors_array, rb_str_new_cstr(err.c_str()));
        }

        return errors_array;

    } catch (const XMLException& e) {
        char* message = XMLString::transcode(e.getMessage());
        VALUE rb_error = rb_str_new_cstr(message);
        XMLString::release(&message);
        rb_raise(rb_eRuntimeError, "XMLException during validation: %s", StringValueCStr(rb_error));
    } catch (const DOMException& e) {
        char* message = XMLString::transcode(e.getMessage());
        VALUE rb_error = rb_str_new_cstr(message);
        XMLString::release(&message);
        rb_raise(rb_eRuntimeError, "DOMException during validation: %s", StringValueCStr(rb_error));
    } catch (...) {
        rb_raise(rb_eRuntimeError, "Unknown exception during validation");
    }

    return Qnil;
}

// RXerces.cache_xpath_validation? - check if XPath validation caching is enabled
static VALUE rxerces_cache_xpath_validation_p(VALUE self) {
    return cache_xpath_validation ? Qtrue : Qfalse;
}

// RXerces.cache_xpath_validation = bool - enable/disable XPath validation caching
static VALUE rxerces_set_cache_xpath_validation(VALUE self, VALUE val) {
    cache_xpath_validation = RTEST(val);
    return val;
}

// RXerces.clear_xpath_validation_cache - clear the XPath validation cache
static VALUE rxerces_clear_xpath_validation_cache(VALUE self) {
    std::lock_guard<std::mutex> lock(xpath_cache_mutex);
    if (xpath_cache_lru_list) {
        xpath_cache_lru_list->clear();
    }
    if (xpath_cache_map) {
        xpath_cache_map->clear();
    }
    return Qnil;
}

// RXerces.xpath_validation_cache_size - return number of cached expressions
static VALUE rxerces_xpath_validation_cache_size(VALUE self) {
    std::lock_guard<std::mutex> lock(xpath_cache_mutex);
    if (!xpath_cache_map) {
        return LONG2NUM(0);
    }
    return LONG2NUM((long)xpath_cache_map->size());
}

// RXerces.xpath_validation_cache_max_size - get max cache size
static VALUE rxerces_xpath_validation_cache_max_size(VALUE self) {
    return LONG2NUM((long)xpath_cache_max_size);
}

// RXerces.xpath_validation_cache_max_size = n - set max cache size
static VALUE rxerces_set_xpath_validation_cache_max_size(VALUE self, VALUE val) {
    // Validate input: must be a non-negative integer
    if (!RB_INTEGER_TYPE_P(val)) {
        rb_raise(rb_eTypeError, "xpath_validation_cache_max_size must be an Integer");
    }

    long size = NUM2LONG(val);
    if (size < 0) {
        rb_raise(rb_eArgError, "xpath_validation_cache_max_size must be non-negative");
    }

    xpath_cache_max_size = (size_t)size;
    return val;
}

// RXerces.xalan_enabled? - check if Xalan is available
static VALUE rxerces_xalan_enabled_p(VALUE self) {
#ifdef HAVE_XALAN
    return Qtrue;
#else
    return Qfalse;
#endif
}

// RXerces.xpath_max_length - get max XPath expression length
static VALUE rxerces_xpath_max_length(VALUE self) {
    return LONG2NUM((long)xpath_max_length);
}

// RXerces.xpath_max_length = n - set max XPath expression length (0 = no limit)
static VALUE rxerces_set_xpath_max_length(VALUE self, VALUE val) {
    // Validate input: must be a non-negative integer
    if (!RB_INTEGER_TYPE_P(val)) {
        rb_raise(rb_eTypeError, "xpath_max_length must be an Integer");
    }

    long size = NUM2LONG(val);
    if (size < 0) {
        rb_raise(rb_eArgError, "xpath_max_length must be non-negative");
    }

    xpath_max_length = (size_t)size;
    return val;
}

extern "C" void Init_rxerces(void) {
    rb_mRXerces = rb_define_module("RXerces");

    // Module-level configuration methods for XPath validation caching
    rb_define_singleton_method(rb_mRXerces, "cache_xpath_validation?", RUBY_METHOD_FUNC(rxerces_cache_xpath_validation_p), 0);
    rb_define_singleton_method(rb_mRXerces, "cache_xpath_validation=", RUBY_METHOD_FUNC(rxerces_set_cache_xpath_validation), 1);
    rb_define_singleton_method(rb_mRXerces, "clear_xpath_validation_cache", RUBY_METHOD_FUNC(rxerces_clear_xpath_validation_cache), 0);
    rb_define_singleton_method(rb_mRXerces, "xpath_validation_cache_size", RUBY_METHOD_FUNC(rxerces_xpath_validation_cache_size), 0);
    rb_define_singleton_method(rb_mRXerces, "xpath_validation_cache_max_size", RUBY_METHOD_FUNC(rxerces_xpath_validation_cache_max_size), 0);
    rb_define_singleton_method(rb_mRXerces, "xpath_validation_cache_max_size=", RUBY_METHOD_FUNC(rxerces_set_xpath_validation_cache_max_size), 1);
    rb_define_singleton_method(rb_mRXerces, "xpath_max_length", RUBY_METHOD_FUNC(rxerces_xpath_max_length), 0);
    rb_define_singleton_method(rb_mRXerces, "xpath_max_length=", RUBY_METHOD_FUNC(rxerces_set_xpath_max_length), 1);
    rb_define_singleton_method(rb_mRXerces, "xalan_enabled?", RUBY_METHOD_FUNC(rxerces_xalan_enabled_p), 0);

    rb_mXML = rb_define_module_under(rb_mRXerces, "XML");

    rb_cDocument = rb_define_class_under(rb_mXML, "Document", rb_cObject);
    rb_undef_alloc_func(rb_cDocument);
    rb_define_singleton_method(rb_cDocument, "parse", RUBY_METHOD_FUNC(document_parse), -1);
    rb_define_method(rb_cDocument, "root", RUBY_METHOD_FUNC(document_root), 0);
    rb_define_method(rb_cDocument, "errors", RUBY_METHOD_FUNC(document_errors), 0);
    rb_define_method(rb_cDocument, "to_s", RUBY_METHOD_FUNC(document_to_s), 0);
    rb_define_alias(rb_cDocument, "to_xml", "to_s");
    rb_define_method(rb_cDocument, "inspect", RUBY_METHOD_FUNC(document_inspect), 0);
    rb_define_method(rb_cDocument, "xpath", RUBY_METHOD_FUNC(document_xpath), 1);
    rb_define_method(rb_cDocument, "at_xpath", RUBY_METHOD_FUNC(document_at_xpath), 1);
    rb_define_alias(rb_cDocument, "at", "at_xpath");
    rb_define_method(rb_cDocument, "css", RUBY_METHOD_FUNC(document_css), 1);
    rb_define_method(rb_cDocument, "at_css", RUBY_METHOD_FUNC(document_at_css), 1);
    rb_define_method(rb_cDocument, "encoding", RUBY_METHOD_FUNC(document_encoding), 0);
    rb_define_method(rb_cDocument, "text", RUBY_METHOD_FUNC(document_text), 0);
    rb_define_alias(rb_cDocument, "content", "text");
    rb_define_method(rb_cDocument, "create_element", RUBY_METHOD_FUNC(document_create_element), 1);
    rb_define_method(rb_cDocument, "children", RUBY_METHOD_FUNC(document_children), 0);
    rb_define_method(rb_cDocument, "element_children", RUBY_METHOD_FUNC(document_element_children), 0);
    rb_define_alias(rb_cDocument, "elements", "element_children");
    rb_define_method(rb_cDocument, "first_element_child", RUBY_METHOD_FUNC(document_first_element_child), 0);
    rb_define_method(rb_cDocument, "last_element_child", RUBY_METHOD_FUNC(document_last_element_child), 0);

    rb_cNode = rb_define_class_under(rb_mXML, "Node", rb_cObject);
    rb_undef_alloc_func(rb_cNode);
    rb_define_method(rb_cNode, "inspect", RUBY_METHOD_FUNC(node_inspect), 0);
    rb_define_method(rb_cNode, "name", RUBY_METHOD_FUNC(node_name), 0);
    rb_define_method(rb_cNode, "namespace", RUBY_METHOD_FUNC(node_namespace), 0);
    rb_define_method(rb_cNode, "text", RUBY_METHOD_FUNC(node_text), 0);
    rb_define_alias(rb_cNode, "content", "text");
    rb_define_method(rb_cNode, "text=", RUBY_METHOD_FUNC(node_text_set), 1);
    rb_define_alias(rb_cNode, "content=", "text=");
    rb_define_method(rb_cNode, "[]", RUBY_METHOD_FUNC(node_get_attribute), 1);
    rb_define_method(rb_cNode, "[]=", RUBY_METHOD_FUNC(node_set_attribute), 2);
    rb_define_alias(rb_cNode, "get_attribute", "[]");
    rb_define_alias(rb_cNode, "attribute", "[]");
    rb_define_method(rb_cNode, "has_attribute?", RUBY_METHOD_FUNC(node_has_attribute_p), 1);
    rb_define_method(rb_cNode, "children", RUBY_METHOD_FUNC(node_children), 0);
    rb_define_method(rb_cNode, "element_children", RUBY_METHOD_FUNC(node_element_children), 0);
    rb_define_alias(rb_cNode, "elements", "element_children");
    rb_define_method(rb_cNode, "first_element_child", RUBY_METHOD_FUNC(node_first_element_child), 0);
    rb_define_method(rb_cNode, "last_element_child", RUBY_METHOD_FUNC(node_last_element_child), 0);
    rb_define_method(rb_cNode, "document", RUBY_METHOD_FUNC(node_document), 0);
    rb_define_method(rb_cNode, "parent", RUBY_METHOD_FUNC(node_parent), 0);
    rb_define_method(rb_cNode, "ancestors", RUBY_METHOD_FUNC(node_ancestors), -1);
    rb_define_method(rb_cNode, "attributes", RUBY_METHOD_FUNC(node_attributes), 0);
    rb_define_method(rb_cNode, "attribute_nodes", RUBY_METHOD_FUNC(node_attribute_nodes), 0);
    rb_define_method(rb_cNode, "next_sibling", RUBY_METHOD_FUNC(node_next_sibling), 0);
    rb_define_method(rb_cNode, "next_element", RUBY_METHOD_FUNC(node_next_element), 0);
    rb_define_method(rb_cNode, "previous_sibling", RUBY_METHOD_FUNC(node_previous_sibling), 0);
    rb_define_method(rb_cNode, "previous_element", RUBY_METHOD_FUNC(node_previous_element), 0);
    rb_define_method(rb_cNode, "add_child", RUBY_METHOD_FUNC(node_add_child), 1);
    rb_define_method(rb_cNode, "remove", RUBY_METHOD_FUNC(node_remove), 0);
    rb_define_alias(rb_cNode, "unlink", "remove");
    rb_define_method(rb_cNode, "inner_html", RUBY_METHOD_FUNC(node_inner_html), 0);
    rb_define_alias(rb_cNode, "inner_xml", "inner_html");
    rb_define_method(rb_cNode, "path", RUBY_METHOD_FUNC(node_path), 0);
    rb_define_method(rb_cNode, "blank?", RUBY_METHOD_FUNC(node_blank_p), 0);
    rb_define_method(rb_cNode, "xpath", RUBY_METHOD_FUNC(node_xpath), 1);
    rb_define_alias(rb_cNode, "search", "xpath");
    rb_define_method(rb_cNode, "at_xpath", RUBY_METHOD_FUNC(node_at_xpath), 1);
    rb_define_alias(rb_cNode, "at", "at_xpath");
    rb_define_method(rb_cNode, "css", RUBY_METHOD_FUNC(node_css), 1);
    rb_define_method(rb_cNode, "at_css", RUBY_METHOD_FUNC(node_at_css), 1);
    rb_define_alias(rb_cNode, "get_attribute", "[]");
    rb_define_alias(rb_cNode, "attribute", "[]");

    rb_cElement = rb_define_class_under(rb_mXML, "Element", rb_cNode);
    rb_undef_alloc_func(rb_cElement);

    rb_cText = rb_define_class_under(rb_mXML, "Text", rb_cNode);
    rb_undef_alloc_func(rb_cText);

    rb_cNodeSet = rb_define_class_under(rb_mXML, "NodeSet", rb_cObject);
    rb_undef_alloc_func(rb_cNodeSet);
    rb_define_method(rb_cNodeSet, "length", RUBY_METHOD_FUNC(nodeset_length), 0);
    rb_define_alias(rb_cNodeSet, "size", "length");
    rb_define_method(rb_cNodeSet, "[]", RUBY_METHOD_FUNC(nodeset_at), 1);
    rb_define_method(rb_cNodeSet, "first", RUBY_METHOD_FUNC(nodeset_first), 0);
    rb_define_method(rb_cNodeSet, "last", RUBY_METHOD_FUNC(nodeset_last), 0);
    rb_define_method(rb_cNodeSet, "empty?", RUBY_METHOD_FUNC(nodeset_empty_p), 0);
    rb_define_method(rb_cNodeSet, "each", RUBY_METHOD_FUNC(nodeset_each), 0);
    rb_define_method(rb_cNodeSet, "to_a", RUBY_METHOD_FUNC(nodeset_to_a), 0);
    rb_define_method(rb_cNodeSet, "text", RUBY_METHOD_FUNC(nodeset_text), 0);
    rb_define_method(rb_cNodeSet, "inner_html", RUBY_METHOD_FUNC(nodeset_inner_html), 0);
    rb_define_method(rb_cNodeSet, "inspect", RUBY_METHOD_FUNC(nodeset_inspect), 0);
    rb_define_alias(rb_cNodeSet, "to_s", "inspect");
    rb_include_module(rb_cNodeSet, rb_mEnumerable);

    rb_cSchema = rb_define_class_under(rb_mXML, "Schema", rb_cObject);
    rb_undef_alloc_func(rb_cSchema);
    rb_define_singleton_method(rb_cSchema, "from_document", RUBY_METHOD_FUNC(schema_from_document), -1);
    rb_define_singleton_method(rb_cSchema, "from_string", RUBY_METHOD_FUNC(schema_from_document), -1);

    rb_define_method(rb_cDocument, "validate", RUBY_METHOD_FUNC(document_validate), 1);

    // Register cleanup handler
    atexit(cleanup_xerces);
}
