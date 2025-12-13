#include "rxerces.h"
#include <xercesc/util/PlatformUtils.hpp>
#include <xercesc/parsers/XercesDOMParser.hpp>
#include <xercesc/dom/DOM.hpp>
#include <xercesc/util/XMLString.hpp>
#include <xercesc/framework/MemBufInputSource.hpp>
#include <xercesc/framework/MemBufFormatTarget.hpp>
#include <xercesc/util/XercesDefs.hpp>
#include <xercesc/dom/DOMXPathResult.hpp>
#include <xercesc/dom/DOMXPathExpression.hpp>
#include <sstream>
#include <vector>

using namespace xercesc;

VALUE rb_mRXerces;
VALUE rb_mXML;
VALUE rb_cDocument;
VALUE rb_cNode;
VALUE rb_cNodeSet;
VALUE rb_cElement;
VALUE rb_cText;
VALUE rb_cSchema;

// Xerces initialization flag
static bool xerces_initialized = false;

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

// Memory management functions
static void document_free(void* ptr) {
    DocumentWrapper* wrapper = (DocumentWrapper*)ptr;
    if (wrapper) {
        if (wrapper->parser) {
            delete wrapper->parser;
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

static void nodeset_free(void* ptr) {
    NodeSetWrapper* wrapper = (NodeSetWrapper*)ptr;
    if (wrapper) {
        xfree(wrapper);
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
    {0, node_free, node_size},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY
};

static const rb_data_type_t nodeset_type = {
    "RXerces::XML::NodeSet",
    {0, nodeset_free, nodeset_size},
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

    NodeWrapper* wrapper = ALLOC(NodeWrapper);
    wrapper->node = node;
    wrapper->doc_ref = doc_ref;

    VALUE rb_node;

    switch (node->getNodeType()) {
        case DOMNode::ELEMENT_NODE:
            rb_node = TypedData_Wrap_Struct(rb_cElement, &node_type, wrapper);
            break;
        case DOMNode::TEXT_NODE:
            rb_node = TypedData_Wrap_Struct(rb_cText, &node_type, wrapper);
            break;
        default:
            rb_node = TypedData_Wrap_Struct(rb_cNode, &node_type, wrapper);
            break;
    }

    // Keep reference to document to prevent GC
    rb_iv_set(rb_node, "@document", doc_ref);

    return rb_node;
}

// RXerces::XML::Document.parse(string)
static VALUE document_parse(VALUE klass, VALUE str) {
    if (!xerces_initialized) {
        try {
            XMLPlatformUtils::Initialize();
            xerces_initialized = true;
        } catch (const XMLException& e) {
            rb_raise(rb_eRuntimeError, "Xerces initialization failed");
        }
    }

    Check_Type(str, T_STRING);
    const char* xml_str = StringValueCStr(str);

    XercesDOMParser* parser = new XercesDOMParser();
    parser->setValidationScheme(XercesDOMParser::Val_Never);
    parser->setDoNamespaces(false);
    parser->setDoSchema(false);

    try {
        MemBufInputSource input((const XMLByte*)xml_str, strlen(xml_str), "memory");
        parser->parse(input);

        DOMDocument* doc = parser->getDocument();

        DocumentWrapper* wrapper = ALLOC(DocumentWrapper);
        wrapper->doc = doc;
        wrapper->parser = parser;

        VALUE rb_doc = TypedData_Wrap_Struct(rb_cDocument, &document_type, wrapper);
        return rb_doc;
    } catch (const XMLException& e) {
        CharStr message(e.getMessage());
        delete parser;
        rb_raise(rb_eRuntimeError, "XML parsing error: %s", message.localForm());
    } catch (const DOMException& e) {
        CharStr message(e.getMessage());
        delete parser;
        rb_raise(rb_eRuntimeError, "DOM error: %s", message.localForm());
    } catch (...) {
        delete parser;
        rb_raise(rb_eRuntimeError, "Unknown XML parsing error");
    }

    return Qnil;
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
    } catch (...) {
        rb_raise(rb_eRuntimeError, "Failed to serialize document");
    }

    return Qnil;
}

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

    try {
        DOMElement* root = doc_wrapper->doc->getDocumentElement();
        if (!root) {
            NodeSetWrapper* wrapper = ALLOC(NodeSetWrapper);
            wrapper->nodes_array = rb_ary_new();
            return TypedData_Wrap_Struct(rb_cNodeSet, &nodeset_type, wrapper);
        }

        DOMXPathNSResolver* resolver = doc_wrapper->doc->createNSResolver(root);
        DOMXPathExpression* expression = doc_wrapper->doc->createExpression(
            XStr(xpath_str).unicodeForm(), resolver);

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

    wrapper->node->setTextContent(XStr(text_str).unicodeForm());

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
    const XMLCh* value = element->getAttribute(XStr(attr_str).unicodeForm());

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
    element->setAttribute(XStr(attr_str).unicodeForm(), XStr(value_str).unicodeForm());

    return attr_value;
}

// node.children
static VALUE node_children(VALUE self) {
    NodeWrapper* wrapper;
    TypedData_Get_Struct(self, NodeWrapper, &node_type, wrapper);

    VALUE doc_ref = rb_iv_get(self, "@document");
    VALUE children = rb_ary_new();

    if (!wrapper->node) {
        return children;
    }

    DOMNodeList* child_nodes = wrapper->node->getChildNodes();
    XMLSize_t count = child_nodes->getLength();

    for (XMLSize_t i = 0; i < count; i++) {
        DOMNode* child = child_nodes->item(i);
        rb_ary_push(children, wrap_node(child, doc_ref));
    }

    return children;
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
    VALUE doc_ref = rb_iv_get(self, "@document");

    try {
        DOMDocument* doc = node_wrapper->node->getOwnerDocument();
        if (!doc) {
            NodeSetWrapper* wrapper = ALLOC(NodeSetWrapper);
            wrapper->nodes_array = rb_ary_new();
            return TypedData_Wrap_Struct(rb_cNodeSet, &nodeset_type, wrapper);
        }

        DOMXPathNSResolver* resolver = doc->createNSResolver(node_wrapper->node);
        DOMXPathExpression* expression = doc->createExpression(
            XStr(xpath_str).unicodeForm(), resolver);

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

// Schema.from_document(schema_doc) or Schema.from_string(xsd_string)
static VALUE schema_from_document(int argc, VALUE* argv, VALUE klass) {
    VALUE schema_source;
    rb_scan_args(argc, argv, "1", &schema_source);

    // Ensure Xerces is initialized
    if (!xerces_initialized) {
        try {
            XMLPlatformUtils::Initialize();
            xerces_initialized = true;
        } catch (const XMLException& e) {
            char* message = XMLString::transcode(e.getMessage());
            VALUE rb_error = rb_str_new_cstr(message);
            XMLString::release(&message);
            rb_raise(rb_eRuntimeError, "Failed to initialize Xerces-C: %s", StringValueCStr(rb_error));
        }
    }

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
// Note: Full schema validation is not yet implemented in this simplified version
static VALUE document_validate(VALUE self, VALUE rb_schema) {
    DocumentWrapper* doc_wrapper;
    TypedData_Get_Struct(self, DocumentWrapper, &document_type, doc_wrapper);

    SchemaWrapper* schema_wrapper;
    TypedData_Get_Struct(rb_schema, SchemaWrapper, &schema_type, schema_wrapper);

    // For now, just return an empty array (indicating no errors)
    // Full XSD validation requires more complex Xerces-C integration
    VALUE errors_array = rb_ary_new();

    // TODO: Implement proper schema validation using Xerces-C's validation APIs
    // This would require:
    // 1. Loading the schema into a Grammar object
    // 2. Creating a validating parser with the grammar
    // 3. Parsing the document with validation enabled
    // 4. Collecting validation errors

    return errors_array;
}

extern "C" void Init_rxerces(void) {
    rb_mRXerces = rb_define_module("RXerces");
    rb_mXML = rb_define_module_under(rb_mRXerces, "XML");

    rb_cDocument = rb_define_class_under(rb_mXML, "Document", rb_cObject);
    rb_undef_alloc_func(rb_cDocument);
    rb_define_singleton_method(rb_cDocument, "parse", RUBY_METHOD_FUNC(document_parse), 1);
    rb_define_method(rb_cDocument, "root", RUBY_METHOD_FUNC(document_root), 0);
    rb_define_method(rb_cDocument, "to_s", RUBY_METHOD_FUNC(document_to_s), 0);
    rb_define_method(rb_cDocument, "to_xml", RUBY_METHOD_FUNC(document_to_s), 0);
    rb_define_method(rb_cDocument, "xpath", RUBY_METHOD_FUNC(document_xpath), 1);

    rb_cNode = rb_define_class_under(rb_mXML, "Node", rb_cObject);
    rb_undef_alloc_func(rb_cNode);
    rb_define_method(rb_cNode, "name", RUBY_METHOD_FUNC(node_name), 0);
    rb_define_method(rb_cNode, "text", RUBY_METHOD_FUNC(node_text), 0);
    rb_define_method(rb_cNode, "content", RUBY_METHOD_FUNC(node_text), 0);
    rb_define_method(rb_cNode, "text=", RUBY_METHOD_FUNC(node_text_set), 1);
    rb_define_method(rb_cNode, "content=", RUBY_METHOD_FUNC(node_text_set), 1);
    rb_define_method(rb_cNode, "[]", RUBY_METHOD_FUNC(node_get_attribute), 1);
    rb_define_method(rb_cNode, "[]=", RUBY_METHOD_FUNC(node_set_attribute), 2);
    rb_define_method(rb_cNode, "children", RUBY_METHOD_FUNC(node_children), 0);
    rb_define_method(rb_cNode, "xpath", RUBY_METHOD_FUNC(node_xpath), 1);

    rb_cElement = rb_define_class_under(rb_mXML, "Element", rb_cNode);
    rb_undef_alloc_func(rb_cElement);

    rb_cText = rb_define_class_under(rb_mXML, "Text", rb_cNode);
    rb_undef_alloc_func(rb_cText);

    rb_cNodeSet = rb_define_class_under(rb_mXML, "NodeSet", rb_cObject);
    rb_undef_alloc_func(rb_cNodeSet);
    rb_define_method(rb_cNodeSet, "length", RUBY_METHOD_FUNC(nodeset_length), 0);
    rb_define_method(rb_cNodeSet, "size", RUBY_METHOD_FUNC(nodeset_length), 0);
    rb_define_method(rb_cNodeSet, "[]", RUBY_METHOD_FUNC(nodeset_at), 1);
    rb_define_method(rb_cNodeSet, "each", RUBY_METHOD_FUNC(nodeset_each), 0);
    rb_define_method(rb_cNodeSet, "to_a", RUBY_METHOD_FUNC(nodeset_to_a), 0);
    rb_include_module(rb_cNodeSet, rb_mEnumerable);

    rb_cSchema = rb_define_class_under(rb_mXML, "Schema", rb_cObject);
    rb_undef_alloc_func(rb_cSchema);
    rb_define_singleton_method(rb_cSchema, "from_document", RUBY_METHOD_FUNC(schema_from_document), -1);
    rb_define_singleton_method(rb_cSchema, "from_string", RUBY_METHOD_FUNC(schema_from_document), -1);

    rb_define_method(rb_cDocument, "validate", RUBY_METHOD_FUNC(document_validate), 1);
}
