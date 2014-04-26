# = FAiR-CG - Finite Automata in Ruby with Code Generation
# Copyright (C) 2010 Richard T. Weeks
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# ---
#
# See FairCG::CxxParserGenerator.

module FairCG; end

# Implements parser generation for C++
#
# This module turns an automaton definition class (or its descendant) into a
# parser generator for C++, which will generate a C++ class (with the same
# name as the Ruby class) that implements the finite automaton described.
#
# Typically, an automaton class (or class descended from one) will extend_with
# this module and then add some definitions to complete the parser generator.
# If necessary, the extended class can call headers with the names of any
# header files necessary for the implementation or header.
#
# == Fields
#
# The class may define the class methods _fields_, _init_fields_, and/or
# _reset_fields_ to determine the user-defined field behavior:
# [_fields_]  Returns the C++ data field definitions.  This typically
#             looks like a group of variables.
# [_init_fields_]  Returns code to initialize the fields when the parser
#                  object is created.
# [_reset_fields_]  Returns code to set fields to any desired pre-action
#                   state.
# All of these methods are optional.
#
# == Actions
#
# Action code is generated using the parser generator class (i.e. +self+) as
# the context; that is, the class object is passed to
# FairCG::FiniteAutomaton::Action#code as the _context_ argument.  If the
# automaton gave blocks for the actions, those blocks are executed as code on
# the parser generator class object (i.e. within the block, +self+ is the parser
# generator class).  If the automaton did not give blocks for one or more
# actions, the _action_code_ class method of the parser generator class will be
# invoked to generate the code for those actions.
#
# The <tt>:char</tt> option specified for an action in the automaton definition
# has special meaning to this module: it defines the name of the variable that
# will receive the value of the current character.  If this option is not
# specified there is no way for action code to access the current character
# value.
#
# == Generating Code
#
# See the generate class method.
module FairCG::CxxParserGenerator
  # Returns the character type for the generated parser.  Redefine this
  # method in the parser generator class to choose a different type, e.g. "char"
  # or "int".
  def char_type
    "wchar_t"
  end
  
  # Returns the name for the generated class.  By default this is the
  # name (minus any containing modules/classes) of the Ruby parser generator
  # class.  Call class_name to set the name of the generated class.
  def cname
    @cname ||= name.split('::').last
  end
  
  # Set the class name to be generated to _name_.  The default value for the
  # generated class name is the name of the Ruby generator class (without
  # any containing modules/classes).
  def class_name(name)
    @cname ||= name
  end
  
  # Call this method to define headers to be included in the implementation
  # of the parser.  Some actions may need to use functions or classes defined
  # either in standard headers or other headers expected to be available to the
  # parser.
  #
  # Pass <tt>:in_header=>true</tt> as the last argument if these headers should
  # be included in the generated header.  This applies independently to each
  # call to this function.
  def headers(*args)
    opts = (args.pop if args.last.is_a? Hash) || {}
    (@headers ||= []).concat(args)
    (@header_headers ||= []).concat(args) if opts[:in_header]
  end

  # Set the namespace in which the class will be defined to _ns_.  _ns_ may
  # be either a String, where nesting levels are separated by '::', or an
  # Array, where each element is a String giving a single namespace identifier.
  def namespace(ns)
    case ns
    when String
      @namespace = ns.split('::')
    when Array
      @namespace = ns.dup
    else
      raise(InvalidArgumentError, "Namespace must be an array or string")
    end
  end
  
  def action_params(action)
    char_v = action.options[:char]
    return char_v ? ("%s %s" % [char_type, char_v]) : ""
  end
  
  # This function maps symbols for state and action names to values that are
  # legal C++ identifiers.  If state or action names are colliding, this method
  # can be redefined to handle the colliding cases, but it must return only
  # valid C++ identifiers.
  def code_name(name)
    name.to_s.gsub(/[^A-Za-z0-9_]/, '_')
  end
  
  def generate_header(header, options = {})
    guard_macro = cname.gsub(/(.)([A-Z])/, '\1_\2').upcase + "_H_#{Time.now.to_i}"
    header.puts "#ifndef " + guard_macro if options[:guard]
    header.puts "#define " + guard_macro if options[:guard]
    header.puts
    if @header_headers
      @header_headers.each do |hfile|
        header.puts(%Q{#include "#{hfile}"})
      end
      header.puts
    end
    namespaces = @namespace || []
    namespaces.each do |ns|
      header.puts "namespace #{ns} {"
    end
    header.puts("class " + cname)
    header.puts("{")
    header.puts("public:")
    header.puts("  #{cname}();")
    header.puts("  bool processChar(#{char_type} ch);")
    header.puts("  bool final() const;")
    header.puts
    header.puts("  struct Fields")
    header.puts("  {")
    header.puts("    " + fields) if respond_to?(:fields)
    header.puts("  };")
    header.puts("  const Fields& fields() {return m_actions;}")
    header.puts
    header.puts("private:")
    header.puts("  struct Actions : public Fields")
    header.puts("  {")
    header.puts("    Actions();")
    header.puts("    void reset_fields();")
    machine_def.actions.values.each do |action|
      header.puts("    void do_#{code_name(action.name)}(#{action_params(action)});")
    end
    header.puts("  };")
    header.puts
    header.puts("  int m_state;")
    header.puts("  Actions m_actions;")
    header.puts("};")
    namespaces.each do |ns|
      header.puts "}"
    end
    header.puts
    header.puts "#endif // " + guard_macro if options[:guard]
  end
  
  def generate_state_enum(impl)                  # StateType
    code_state_names = []
    impl.puts("  enum StateType {")
    (machine_def.state_names | [:error]).each do |name|
      name = code_name(name)
      raise "State name collision (#{name})" if code_state_names.include?(name)
      code_state_names << name
      impl.puts("    s_#{code_name(name)},")
    end
    impl.puts("  };")
  end
  
  def generate_char_class_enum(impl)             # CharacterClass
    impl.puts("  enum CharacterClass {")
    machine_def.character_classes.each_with_index do |cc, i|
      impl.puts("    cc_#{i}, // %p" % [cc])
    end
    impl.puts("    cc_other")
    impl.puts("  };")
  end
  
  def generate_action_enum(impl)                 # ActionType
    code_action_names = []
    impl.puts("  enum ActionType {")
    machine_def.actions.each do |name, action|
      name = code_name(name)
      raise "Action name collision (#{name})" if code_action_names.include?(name)
      code_action_names << name
      impl.puts("    a_%s = 0x%08X," % [name, 1 << action.order_key])
    end
    impl.puts("  };")
  end
  
  def generate_transition_table(impl)            # parserTransitions
    impl.puts("  StateType parserTransitions[#{machine_def.state_names.length}][cc_other + 1] = {")
    machine_def.state_names.each do |name|
      info = machine_def.state_info(name)
      states = []
      machine_def.character_classes.each do |cc|
        states << info.transition_for(cc[0]).end_state
      end
      states << info.transition_for(:other).end_state
      states.collect! {|s| "s_#{code_name(s)}"}
      impl.puts("    {" + states.join(", ") + "},")
    end
    impl.puts("  };")
  end
  
  def generate_actions_table(impl)               # parserActions
    impl.puts("  int parserActions[#{machine_def.state_names.length}][cc_other + 1] = {")
    machine_def.state_names.each do |name|
      info = machine_def.state_info(name)
      actions = []
      machine_def.character_classes.each do |cc|
        actions << info.transition_for(cc[0]).actions
      end
      actions << info.transition_for(:other).actions
      actions.collect! {|ta| ta.empty? ? "0" : ta.collect {|a| "a_#{code_name(a)}"}.join("|")}
      impl.puts("    {" + actions.join(", ") + "},")
    end
    impl.puts("  };")
  end
  
  def generate_char_classification_fn(impl)      # parserClassify
    impl.puts("  CharacterClass parserClassify(#{char_type} ch)")
    impl.puts("  {")
    impl.puts("    switch(ch)")
    impl.puts("    {")
    machine_def.character_classes.each_with_index do |cc, i|
      cc.each do |c|
        impl.puts("    case #{c}:")
      end
      impl.puts("      return cc_#{i};")
    end
    impl.puts("    default:")
    impl.puts("      return cc_other;")
    impl.puts("    }")
    impl.puts("  }")
  end
  
  def generate_final_states_fn(impl)             # parserInFinalState
    impl.puts("  bool parserInFinalState(int state)")
    impl.puts("  {")
    impl.puts("    switch (state)")
    impl.puts("    {")
    machine_def.state_names.each do |name|
      impl.puts("    case s_#{code_name(name)}:") if machine_def.state_info(name).final
    end
    impl.puts("      return true;")
    impl.puts("    }")
    impl.puts("    return false;")
    impl.puts("  }")
  end
  
  def generate_implementation(impl, options = {})
    (@headers || []).each do |header|
      impl.puts(%Q{#include "#{header}"})
    end
    impl.puts
    
    if @namespace
      namespaces = @namespace.join("::")
      impl.puts("using namespace #{namespaces};")
      impl.puts
    end
    
    # FSM tables
    impl.puts("namespace {")
    generate_state_enum(impl)
    generate_char_class_enum(impl)
    generate_action_enum(impl)
    generate_transition_table(impl)
    generate_actions_table(impl)
    generate_char_classification_fn(impl)
    generate_final_states_fn(impl)
    impl.puts("}")
    impl.puts
    
    # Parser constructor
    impl.puts("#{cname}::#{cname}()")
    impl.puts("{")
    impl.puts("  m_state = s_#{code_name(machine_def.start_state)};")
    impl.puts("}")
    impl.puts
    
    # Process character
    impl.puts("bool #{cname}::processChar(#{char_type} ch)")
    impl.puts("{")
    unless machine_def.state_info(:error)
      impl.puts("  if (m_state == s_#{code_name(:error)})")
      impl.puts("  {")
      impl.puts("    return false;")
      impl.puts("  }")
    end
    impl.puts("  m_actions.reset_fields();") if respond_to?(:reset_fields)
    impl.puts("  CharacterClass clsCh = parserClassify(ch);")
    impl.puts("  int newState = parserTransitions[m_state][clsCh];")
    impl.puts("  int actions = parserActions[m_state][clsCh];")
    actions_in_order.each do |action|
      impl.puts("  if ((actions & a_#{code_name(action.name)}) != 0)")
      impl.puts("  {")
      impl.puts("    m_actions.do_#{code_name(action.name)}(#{"ch" if action.options[:char]});")
      impl.puts("  }")
    end
    impl.puts("  m_state = newState;")
    impl.puts("  return (m_state != s_#{code_name(:error)});")
    impl.puts("}")
    impl.puts
    
    # Check for final state
    impl.puts("bool #{cname}::final() const")
    impl.puts("{")
    impl.puts("  return parserInFinalState(m_state);")
    impl.puts("}")
    impl.puts
    
    # Field initialization
    impl.puts("#{cname}::Actions::Actions()")
    impl.puts("{")
    impl.puts("  " + init_fields) if respond_to?(:init_fields)
    impl.puts("}")
    impl.puts
    
    # Field reset -- called from processChar() before actions are executed
    impl.puts("void #{cname}::Actions::reset_fields()")
    impl.puts("{")
    impl.puts("  " + reset_fields) if respond_to?(:reset_fields)
    impl.puts("}")
    impl.puts
    
    # Actions
    machine_def.actions.each_value do |action|
      impl.puts("void #{cname}::Actions::do_#{code_name(action.name)}(#{action_params(action)})")
      impl.puts("{")
      impl.puts("  " + action.code(self) + ";")
      impl.puts("}")
      impl.puts
    end
    
    return nil
  end
  
  # Generate the parser code
  #
  # This method generates the parser code and sends it to various possible
  # destinations:
  # [<em>:file_base</em>]  Send the header to <em>:file_base</em>.h and the
  #                        implementation to <em>:file_base</em>.cpp.
  #                        <em>:file_base</em>.cpp will include
  #                        <em>:file_base</em>.h.
  # [<em>:to => stream</em>]  Send the code unit defining the parser to the
  #                           indicated stream.  The class definition will be
  #                           written as part of the code unit.
  # [<em>:to => [header, impl]</em>]  Send the code unit defining the parser
  #                                   to _impl_ and the corresponding header
  #                                   to _header_.  The class definition will
  #                                   be written to both _header_ and _impl_.
  #
  # The <tt>:message</tt> option may be used to output a message comment at the
  # top of the generated files, e.g.
  #   :message => "Autogenerated by #{__FILE__}"
  def generate(options = {:to => $stdout})
    options = options.dup
    file_base = options.delete(:file_base)
    includes = []
    
    files_opened = []
    begin
      header_options = {}
      put_header_in_impl = false
      if file_base
        header_file = file_base + ".h"
        files_opened << (header = File.open(header_file, 'w'))
        header_options[:guard] = true
        includes.unshift(File.basename(header_file))
        files_opened << (impl = File.open(file_base + ".cpp", 'w'))
      else
        if options[:to].is_a?(Array)
          header, impl = options[:to]
        else
          header = impl = options[:to]
        end
        put_header_in_impl = impl != header
      end
      
      impl.puts("// " + options[:message]) if options[:message]
      
      includes.each do |include|
        impl.puts(%Q{#include "#{include}"})
      end
      impl.puts
      
      header.puts("// " + options[:message]) if options[:message] && header != impl
      
      generate_header(header, header_options)
      generate_header(impl, header_options) if put_header_in_impl
      generate_implementation(impl, options)
    ensure
      files_opened.each {|file| file.close}
    end
  end
end
