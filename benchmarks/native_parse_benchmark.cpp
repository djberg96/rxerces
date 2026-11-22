// Isolate Xerces parser construction, parsing, and document destruction.
// Build/run instructions are in benchmarks/README.md.
#include <xercesc/util/PlatformUtils.hpp>
#include <xercesc/util/XMLUni.hpp>
#include <xercesc/util/XMLString.hpp>
#include <xercesc/parsers/XercesDOMParser.hpp>
#include <xercesc/framework/MemBufInputSource.hpp>
#include <xercesc/dom/DOM.hpp>
#include <algorithm>
#include <chrono>
#include <iomanip>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

using namespace xercesc;
using Clock = std::chrono::steady_clock;

static std::unique_ptr<XercesDOMParser> parser_for(bool dtd_scanner) {
    std::unique_ptr<XercesDOMParser> parser(new XercesDOMParser());
    if (dtd_scanner) parser->useScanner(XMLUni::fgDGXMLScanner);
    parser->setLoadExternalDTD(false);
    parser->setDisableDefaultEntityResolution(true);
    parser->setValidationScheme(XercesDOMParser::Val_Never);
    parser->setDoNamespaces(true);
    parser->setDoSchema(false);
    return parser;
}

int main(int argc, char** argv) {
    XMLPlatformUtils::Initialize();
    std::cout << "elements,bytes,mode,construction_us,parse_us,release_us,total_us\n";
    for (size_t count : {1, 100, 1000, 10000}) {
        if (argc > 1 && count != std::stoul(argv[1])) continue;
        std::string xml = "<root>";
        for (size_t i = 0; i < count; ++i) {
            xml += "<item id=\"1\"><name>Hello</name></item>";
        }
        xml += "</root>";
        const size_t iterations = argc > 2 ? std::stoul(argv[2]) : std::min(size_t(10000), size_t(100000) / count);
        if (iterations == 0) return 1;
        for (bool dtd_scanner : {false, true}) {
            for (bool reuse : {false, true}) {
                const std::string mode = std::string(dtd_scanner ? "dtd_" : "default_") + (reuse ? "reuse" : "fresh");
                if (argc > 3 && mode != argv[3]) continue;
                std::vector<std::vector<double>> samples;
                for (int sample = 0; sample < 3; ++sample) {
                    auto cached = reuse ? parser_for(dtd_scanner) : nullptr;
                    double construction = 0, parsing = 0, release = 0;
                    for (size_t iteration = 0; iteration < iterations; ++iteration) {
                        const auto start = Clock::now();
                        auto fresh = reuse ? nullptr : parser_for(dtd_scanner);
                        auto* parser = reuse ? cached.get() : fresh.get();
                        const auto ready = Clock::now();
                        MemBufInputSource input(reinterpret_cast<const XMLByte*>(xml.data()), xml.size(), "memory");
                        input.setCopyBufToStream(false);
                        parser->parse(input);
                        if (parser->getErrorCount() || !parser->getDocument()->getDocumentElement()) return 1;
                        const auto parsed = Clock::now();
                        if (reuse) parser->adoptDocument()->release();
                        else fresh.reset();
                        const auto released = Clock::now();
                        construction += std::chrono::duration<double, std::micro>(ready - start).count();
                        parsing += std::chrono::duration<double, std::micro>(parsed - ready).count();
                        release += std::chrono::duration<double, std::micro>(released - parsed).count();
                    }
                    samples.push_back({construction / iterations, parsing / iterations, release / iterations});
                }
                // Select the sample with median total time so phases add up.
                std::sort(samples.begin(), samples.end(), [](const std::vector<double>& a, const std::vector<double>& b) {
                    return a[0] + a[1] + a[2] < b[0] + b[1] + b[2];
                });
                const auto& result = samples[1];
                std::cout << count << ',' << xml.size() << ','
                          << mode
                          << std::fixed << std::setprecision(3) << ',' << result[0] << ',' << result[1]
                          << ',' << result[2] << ',' << result[0] + result[1] + result[2] << '\n' << std::flush;
            }
        }
    }
    XMLPlatformUtils::Terminate();
}
