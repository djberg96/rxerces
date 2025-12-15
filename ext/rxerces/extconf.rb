require 'mkmf'

# Force C++ compiler for the extension
$CXXFLAGS << " -std=c++11"

# Try to find Xerces-C via homebrew on macOS
if RUBY_PLATFORM =~ /darwin/
  homebrew_prefix = `brew --prefix xerces-c 2>/dev/null`.chomp
  if !homebrew_prefix.empty? && File.directory?(homebrew_prefix)
    $INCFLAGS << " -I#{homebrew_prefix}/include"
    $LDFLAGS << " -L#{homebrew_prefix}/lib"
  end
end

# Check for Xerces-C library
unless have_library('xerces-c')
  puts "Xerces-C library not found. Please install it:"
  puts "  macOS: brew install xerces-c"
  puts "  Ubuntu/Debian: sudo apt-get install libxerces-c-dev"
  puts "  Fedora/RHEL: sudo yum install xerces-c-devel"
  exit 1
end

# Use C++ for header checking
# We check by trying to find the library itself rather than header
unless find_header('xercesc/util/PlatformUtils.hpp')
  # Header check failed, but library exists, so we'll proceed with a warning
  puts "Warning: Xerces-C headers not automatically detected, but library is present."
  puts "Proceeding with compilation..."
end

# Check for Xalan-C (optional for enhanced XPath support)
# Use dir_config which handles --with-xalan-dir and --with-xalan-include/lib
dir_config('xalan')

# Also try to auto-detect in common locations
if RUBY_PLATFORM =~ /darwin/
  homebrew_xalan = `brew --prefix xalan-c 2>/dev/null`.chomp
  if !homebrew_xalan.empty? && File.directory?(homebrew_xalan)
    $INCFLAGS << " -I#{homebrew_xalan}/include" unless $INCFLAGS.include?("-I#{homebrew_xalan}/include")
    $LDFLAGS << " -L#{homebrew_xalan}/lib" unless $LDFLAGS.include?("-L#{homebrew_xalan}/lib")
  end
end

# Try standard locations
xalan_found_prefix = nil
['/usr/local', '/opt/local', '/usr'].each do |prefix|
  if File.directory?("#{prefix}/include/xalanc")
    $INCFLAGS << " -I#{prefix}/include" unless $INCFLAGS.include?("-I#{prefix}/include")
    $LDFLAGS << " -L#{prefix}/lib" unless $LDFLAGS.include?("-L#{prefix}/lib")
    xalan_found_prefix = prefix
    break
  end
end

# Check for Xalan libraries
# Note: We skip the header check because Xalan C++ headers require C++ compilation
# which mkmf's find_header doesn't handle well. The library check is sufficient.
if have_library('xalanMsg') && have_library('xalan-c')
  $CXXFLAGS << " -DHAVE_XALAN"
  # Add rpath so the dynamic libraries can be found at runtime
  if xalan_found_prefix
    $LDFLAGS << " -Wl,-rpath,#{xalan_found_prefix}/lib"
  end
  puts "Xalan-C found: Full XPath 1.0 support enabled"
else
  puts "Xalan-C not found: Using Xerces XPath subset"
  puts "For full XPath 1.0 support, install Xalan-C:"
  puts "  macOS: Build from source (no homebrew formula available)"
  puts "  Linux: May be available via package manager"
  puts "  Or specify: --with-xalan-dir=/path/to/xalan"
end

create_makefile('rxerces/rxerces')
