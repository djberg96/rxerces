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
xalan_prefix = '/usr/local'
if File.directory?("#{xalan_prefix}/include/xalanc")
  $INCFLAGS << " -I#{xalan_prefix}/include"
  $LDFLAGS << " -L#{xalan_prefix}/lib"

  # Check for both Xalan libraries - xalanMsg must be checked first for linking order
  if have_library('xalanMsg') && have_library('xalan-c')
    $CXXFLAGS << " -DHAVE_XALAN"
    # Add rpath so the dynamic libraries can be found at runtime
    $LDFLAGS << " -Wl,-rpath,#{xalan_prefix}/lib"
    puts "Xalan-C found: Full XPath 1.0 support enabled"
  else
    puts "Warning: Xalan-C headers found but libraries not available"
    puts "Falling back to Xerces XPath subset"
  end
else
  puts "Xalan-C not found: Using Xerces XPath subset"
  puts "For full XPath 1.0 support, install Xalan-C from source"
end

create_makefile('rxerces/rxerces')
