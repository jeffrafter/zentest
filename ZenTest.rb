#!/usr/local/bin/ruby -swI .

$r = false unless defined? $r # reverse mapping for testclass names

$ZENTEST = true
$TESTING = false unless defined? $TESTING
require 'test/unit/testcase' # helps required modules

class ZenTest

  VERSION = '2.2.0'

  if $TESTING then
    attr_reader :missing_methods
    attr_writer :test_klasses
    attr_writer :klasses
  else
    def missing_methods; raise "Something is wack"; end
  end

  def initialize
    @result = []
    @test_klasses = {}
    @klasses = {}
    @error_count = 0
    @inherited_methods = {}
    @missing_methods = {} # key = klassname, val = array of methods
  end

  def load_file(file)
    puts "# loading #{file} // #{$0}" if $DEBUG

    unless file == $0 then
      begin
	require "#{file}"
      rescue LoadError => err
	puts "Could not load #{file}: #{err}"
      end
    else
      puts "# Skipping loading myself (#{file})" if $DEBUG
    end
  end

  def get_class(klassname)
    begin
      #	p Module.constants
      klass = Module.const_get(klassname.intern)
      puts "# found #{klass.name}" if $DEBUG
    rescue NameError
      # TODO use catch/throw to exit block as soon as it's found?
      # TODO or do we want to look for potential dups?
      ObjectSpace.each_object(Class) { |cls|
	if cls.name =~ /(^|::)#{klassname}$/ then
	  klass = cls
	  klassname = cls.name
	end
      }
      puts "# searched and found #{klass.name}" if klass and $DEBUG
    end

    if klass.nil? and not $TESTING then
      puts "Could not figure out how to get #{klassname}..."
      puts "Report to support-zentest@zenspider.com w/ relevant source"
    end

    return klass
  end

  def get_methods_for(klass, full=false)
    klass = self.get_class(klass) if klass.kind_of? String

    # WTF? public_instance_methods: default vs true vs false = 3 answers
    public_methods = klass.public_instance_methods(false)
    public_methods -= Kernel.methods unless full
    klassmethods = {}
    public_methods.each do |meth|
      puts "# found method #{meth}" if $DEBUG
      klassmethods[meth] = true
    end
    return klassmethods
  end

  def get_inherited_methods_for(klass, full)
    klass = self.get_class(klass) if klass.kind_of? String

    klassmethods = {}
    if (klass.class.method_defined?(:superclass)) then
      superklass = klass.superclass
      if superklass then
        the_methods = superklass.instance_methods(true)
        
        # generally we don't test Object's methods...
        unless full then
          the_methods -= Object.instance_methods(true)
          the_methods -= Kernel.methods # FIX (true) - check 1.6 vs 1.8
        end
      
        the_methods.each do |meth|
          klassmethods[meth] = true
        end
      end
    end
    return klassmethods
  end

  def is_test_class(klass)
    klass = klass.to_s
    klasspath = klass.split(/::/)
    a_bad_classpath = klasspath.find do |s| s !~ ($r ? /Test$/ : /^Test/) end
    return a_bad_classpath.nil?
  end

  def convert_class_name(name)
    name = name.to_s

    if self.is_test_class(name) then
      if $r then
        name = name.gsub(/Test($|::)/, '\1') # FooTest::BlahTest => Foo::Blah
      else
        name = name.gsub(/(^|::)Test/, '\1') # TestFoo::TestBlah => Foo::Blah
      end
    else
      if $r then
        name = name.gsub(/($|::)/, 'Test\1') # Foo::Blah => FooTest::BlahTest
      else
        name = name.gsub(/(^|::)/, '\1Test') # Foo::Blah => TestFoo::TestBlah
      end
    end

    return name
  end

  def scan_files(*files)
    puts "# Code Generated by ZenTest v. #{VERSION}"
    puts "# run against: #{files.join(', ')}" if $DEBUG

    assert_count = {}
    method_count = {}
    assert_count.default = 0
    method_count.default = 0
    klassname = nil

    files.each do |path|
      is_loaded = false

      # if reading stdin, slurp the whole thing at once
      file = (path == "-" ? $stdin.read : File.new(path))

      file.each_line do |line|

	method_count[klassname] += 1 if klassname and line =~ /^\s*def/
	assert_count[klassname] += 1 if klassname and line =~ /assert|flunk/

	if line =~ /^\s*(?:class|module)\s+([\w:]+)/ then
	  klassname = $1

	  if line =~ /\#\s*ZenTest SKIP/ then
	    klassname = nil
	    next
	  end

          full = false
	  if line =~ /\#\s*ZenTest FULL/ then
	    full = true
	  end

	  unless is_loaded then
            unless path == "-" then
              self.load_file(path)
            else
              eval file, TOPLEVEL_BINDING
            end
            is_loaded = true
	  end

	  klass = self.get_class(klassname)
	  next if klass.nil?
	  klassname = klass.name # refetch to get full name
	  
	  is_test_class = self.is_test_class(klassname)
	  target = is_test_class ? @test_klasses : @klasses

	  # record public instance methods JUST in this class
	  target[klassname] = self.get_methods_for(klass, full)
	  
	  # record ALL instance methods including superclasses (minus Object)
	  @inherited_methods[klassname] = 
            self.get_inherited_methods_for(klass, full)
	end # if /class/
      end # IO.foreach
    end # files

    result = []
    method_count.each_key do |classname|

      entry = {}

      next if is_test_class(classname)
      testclassname = convert_class_name(classname)
      a_count = assert_count[testclassname]
      m_count = method_count[classname]
      ratio = a_count.to_f / m_count.to_f * 100.0

      entry['n'] = classname
      entry['r'] = ratio
      entry['a'] = a_count
      entry['m'] = m_count

      result.push entry
    end

    sorted_results = result.sort { |a,b| b['r'] <=> a['r'] }

    printf "# %25s: %4s / %4s = %6s%%\n", "classname", "asrt", "meth", "ratio"
    sorted_results.each do |e|
      printf "# %25s: %4d / %4d = %6.2f%%\n", e['n'], e['a'], e['m'], e['r']
    end

    if $DEBUG then
      puts "# found classes: #{@klasses.keys.join(', ')}"
      puts "# found test classes: #{@test_klasses.keys.join(', ')}"
    end

  end

  def add_missing_method(klassname, methodname)
    @result.push "# ERROR method #{klassname}\##{methodname} does not exist (1)" if $DEBUG and not $TESTING
    @error_count += 1
    @missing_methods[klassname] ||= {}
    @missing_methods[klassname][methodname] = true
  end

  @@method_map = {
    '[]'  => 'index',
    '[]=' => 'index_equals',
    '<<'  => 'append',
    '*'   => 'times',
    '+'   => 'plus',
    '=='  => 'equals',
  }

  @@method_map.merge!(@@method_map.invert)

  def normal_to_test(name)
    name = @@method_map[name] if @@method_map.has_key? name
    "test_#{name}"
  end

  def test_to_normal(name)
    name = name.sub(/^test_/, '')
    name = @@method_map[name] if @@method_map.has_key? name
    name
  end

  def analyze
    # walk each known class and test that each method has a test method
    @klasses.each_key do |klassname|
      testklassname = self.convert_class_name(klassname)
      if @test_klasses[testklassname] then
	methods = @klasses[klassname]
	testmethods = @test_klasses[testklassname]

	# check that each method has a test method
	@klasses[klassname].each_key do | methodname |
	  testmethodname = normal_to_test(methodname)
	  unless testmethods[testmethodname] then
	    unless testmethods.keys.find { |m| m =~ /#{testmethodname}(_\w+)+$/ } then
	      self.add_missing_method(testklassname, testmethodname)
	    end
	  end # testmethods[testmethodname]
	end # @klasses[klassname].each_key
      else # ! @test_klasses[testklassname]
	puts "# ERROR test class #{testklassname} does not exist" if $DEBUG
	@error_count += 1

	@missing_methods[testklassname] ||= {}
	@klasses[klassname].keys.each do | methodname |
	  testmethodname = normal_to_test(methodname)
	  @missing_methods[testklassname][testmethodname] = true
	end
      end # @test_klasses[testklassname]
    end # @klasses.each_key

    ############################################################
    # now do it in the other direction...

    @test_klasses.each_key do |testklassname|

      klassname = self.convert_class_name(testklassname)

      if @klasses[klassname] then
	methods = @klasses[klassname]
	testmethods = @test_klasses[testklassname]

	# check that each test method has a method
	testmethods.each_key do | testmethodname |
	  # FIX: need to convert method name properly
	  if testmethodname =~ /^test_/ then
	    methodname = test_to_normal(testmethodname)

	    # TODO think about allowing test_misc_.*

	    # try the current name
	    orig_name = methodname.dup
	    found = false
	    @inherited_methods[klassname] ||= {}
	    until methodname == "" or methods[methodname] or @inherited_methods[klassname][methodname] do
	      # try the name minus an option (ie mut_opt1 -> mut)
	      if methodname.sub!(/_[^_]+$/, '') then
		if methods[methodname] or @inherited_methods[klassname][methodname] then
		  found = true
		end
	      else
		break # no more substitutions will take place
	      end
	    end # methodname == "" or ...

	    unless found or methods[methodname] or methodname == "initialize" then
	      self.add_missing_method(klassname, orig_name)
	    end

	  else # not a test_.* method
	    unless testmethodname =~ /^util_/ then
	      puts "# WARNING Skipping #{testklassname}\##{testmethodname}" if $DEBUG
	    end
	  end # testmethodname =~ ...
	end # testmethods.each_key
      else # ! @klasses[klassname]
	puts "# ERROR class #{klassname} does not exist" if $DEBUG
	@error_count += 1

	@missing_methods[klassname] ||= {}
	@test_klasses[testklassname].keys.each do |testmethodname|
	  # TODO: need to convert method name properly
	  methodname = test_to_normal(testmethodname)
	  @missing_methods[klassname][methodname] = true
	end
      end # @klasses[klassname]
    end # @test_klasses.each_key
  end

  def generate_code

    if @missing_methods.size > 0 then
      @result.push ""
      @result.push "require 'test/unit' unless defined? $ZENTEST and $ZENTEST"
      @result.push ""
    end

    indentunit = "  "

    @missing_methods.keys.sort.each do |fullklasspath|

      methods = @missing_methods[fullklasspath] || {}

      next if methods.empty?

      indent = 0
      is_test_class = self.is_test_class(fullklasspath)
      klasspath = fullklasspath.split(/::/)
      klassname = klasspath.pop

      klasspath.each do | modulename |
	@result.push indentunit*indent + "module #{modulename}"
	indent += 1
      end
      @result.push indentunit*indent + "class #{klassname}" + (is_test_class ? " < Test::Unit::TestCase" : '')
      indent += 1

      meths = []
      methods.keys.sort.each do |method|
	meth = []
	meth.push indentunit*indent + "def #{method}"
	indent += 1
	meth.push indentunit*indent + "raise NotImplementedError, 'Need to write #{method}'"
	indent -= 1
	meth.push indentunit*indent + "end"
	meths.push meth.join("\n")
      end

      @result.push meths.join("\n\n")

      indent -= 1
      @result.push indentunit*indent + "end"
      klasspath.each do | modulename |
	indent -= 1
	@result.push indentunit*indent + "end"
      end
      @result.push ''
    end

    @result.push "# Number of errors detected: #{@error_count}"
    @result.push ''
  end

  def result
    return @result.join("\n")
  end

  def ZenTest.fix(*files)
    zentest = ZenTest.new
    zentest.scan_files(*files)
    zentest.analyze
    zentest.generate_code
    return zentest.result
  end

end

if __FILE__ == $0 then
  $TESTING = true # for ZenWeb and any other testing infrastructure code

  if defined? $v then
    puts "#{File.basename $0} v#{ZenTest::VERSION}"
    exit 0
  end

  if defined? $h then
    puts "usage: #{File.basename $0} [-h -v] test-and-implementation-files..."
    puts "  -h display this information"
    puts "  -v display version information"
    puts "  -r Reverse mapping (ClassTest instead of TestClass)"
    puts "  -e (Rapid XP) eval the code generated instead of printing it"
    exit 0
  end

  code = ZenTest.fix(*ARGV)
  if defined? $e then
    require 'test/unit'
    eval code
  else
    print code
  end
end
