#include "rxerces.h"
#include <xercesc/util/PlatformUtils.hpp>
#include <xercesc/parsers/XercesDOMParser.hpp>
#include <xercesc/dom/DOM.hpp>
#include <xercesc/util/XMLString.hpp>
#include <xercesc/framework/MemBufInputSource.hpp>
#include <xercesc/framework/MemBufFormatTarget.hpp>
#include <sstream>

using namespace xercesc;

VALUE rb_mRXerces;
VALUE rb_mXML;
VALUE rb_cDocument;
VALUE rb_cNode;
VALUE rb_cNodeSet;
VALUE rb_cElement;
VALUE rb_cText;

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

static size_t document_size(const void* ptr) {
    return sizeof(DocumentWrapper);
}

static size_t node_size(const void* ptr) {
    return sizeof(NodeWrapper);
}

static size_t nodeset_size(const void* ptr) {
    return sizeof(NodeSetWrapper);
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
    Check_Type(path, T_STRING);

    // For now, return empty NodeSet (full XPath requires additional implementation)
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
    Check_Type(path, T_STRING);

    // For basic implementation, return empty NodeSet
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

extern "C" void Init_rxerces(void) {
    rb_mRXerces = rb_define_module("RXerces");
    rb_mXML = rb_define_module_under(rb_mRXerces, "XML");

    rb_cDocument = rb_define_class_under(rb_mXML, "Document", rb_cObject);
    rb_define_singleton_method(rb_cDocument, "parse", RUBY_METHOD_FUNC(document_parse), 1);
    rb_define_method(rb_cDocument, "root", RUBY_METHOD_FUNC(document_root), 0);
    rb_define_method(rb_cDocument, "to_s", RUBY_METHOD_FUNC(document_to_s), 0);
    rb_define_method(rb_cDocument, "to_xml", RUBY_METHOD_FUNC(document_to_s), 0);
    rb_define_method(rb_cDocument, "xpath", RUBY_METHOD_FUNC(document_xpath), 1);

    rb_cNode = rb_define_class_under(rb_mXML, "Node", rb_cObject);
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
    rb_cText = rb_define_class_under(rb_mXML, "Text", rb_cNode);

    rb_cNodeSet = rb_define_class_under(rb_mXML, "NodeSet", rb_cObject);
    rb_define_method(rb_cNodeSet, "length", RUBY_METHOD_FUNC(nodeset_length), 0);
    rb_define_method(rb_cNodeSet, "size", RUBY_METHOD_FUNC(nodeset_length), 0);
    rb_define_method(rb_cNodeSet, "[]", RUBY_METHOD_FUNC(nodeset_at), 1);
    rb_define_method(rb_cNodeSet, "each", RUBY_METHOD_FUNC(nodeset_each), 0);
    rb_define_method(rb_cNodeSet, "to_a", RUBY_METHOD_FUNC(nodeset_to_a), 0);
    rb_include_module(rb_cNodeSet, rb_mEnumerable);
}
