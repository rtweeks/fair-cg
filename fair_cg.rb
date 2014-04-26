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
# == Getting Started
#
# See FairCG::FiniteAutomaton.

# Namespace for FAiR-CG
module FairCG; end

# The FiniteAutomaton class provides a domain specific language in Ruby for
# defining a finite automaton (a.k.a. finite state machine).  This language
# allows explicit definition of actions, states, and transitions.  When the
# class is loaded into the Ruby interpreter, methods on the class describe the
# machine definition in a way that is convenient for generating code to
# implement the finite automaton.
#
# == Defining an Automaton
#
# Each automaton definition begins by deriving a class from FiniteAutomaton,
# e.g.
#   class MyAutomaton < FiniteAutomaton
#     .
#     .
#     .
#   end
#
# == Defining Actions
#
# Action declarations must precede state definitions in your automaton.  The
# order of the action declarations determines the order in which the actions
# will be presented in the resulting object model and will be enforced within
# the transitions; if the actions in a transition are listed out of order an
# exception will be thrown when the automaton class is loaded.  The order of
# actions is likely to have significance to code generators.
#
# Use the action method to define an action.  Action definitions can be given
# in two ways:
# 1. Give a block to the action definition.  This block will be invoked as if
#    it were a method declared on the _context_ object passed to
#    FiniteAutomaton::Action#code.
#      action :append, :char => "ch" do
#        "symbol += ch;"
#      end
# 2. Define an <em>action_code</em> method on the context object that accepts
#    one or two arguments.  The first argument is the name of the action to
#    implement.  If a second argument is specified, it receives the options
#    declared for the action (see the _options_ argument of the action method).
#      action :append, :char => "ch"
# See the documentation of the code generator for information on the object
# passed as the context for getting code from the action.  Code generator
# modules typically pass +self+ as the context object.
#
# == Defining States
#
# States are defined after actions using the state method.  State definitions
# give the (unique) name of the state and, in the case of final states, the
# <tt>:final=>true</tt> option.  <b>The first state defined</b> will be the
# initial state for the automaton.  The block given to the state method defines
# the transitions possible _from_ that state.
#
# Example: defining a non-final state
#   state :int_part do
#     .
#     .
#     .
#   end
#
# Example: defining a final state with no transitions
#   state :done, :final=>true
#
# The state <tt>:error</tt> is a special case.  For each character class 
# without a defined transition out of the state there is an implicit transition
# to <tt>:error</tt> without any actions.
#
# == Defining Transitions
#
# Calls to transition (State#transition) within the block of a state call 
# define transitions out of that state.  The hash passed to transition
# should contain a single entry, where the key is the set of characters causing
# the transition and the value giving the state resulting from the transition.
# If a dash character occurs in the key (but not at the beginning or end) it
# includes all of the characters between the characters before and after the
# dash.  E.g. the key "0-9" is equivalent to "0123456789".  If the key is
# <tt>:default</tt>, the transition becomes the default transition from the 
# state, instead of the implicit default transition to <tt>:error</tt>.  The
# key may also be given as a Range of Integers (e.g. <tt>0x0660..0x0669</tt>).
#
# Example:
#   transition "Ee" => :exponent
#
# If a block is given to the transition, it defines the actions to execute
# when the transition is made.  To define the actions, make a call to the
# action name within the block.  If calling multiple actions, make sure the
# calls are in the same order that the actions are defined; out of order calls
# will cause an exception when the automaton class is loaded.  The implicit
# default transition has no associated actions.
#
# == Generating Code
#
# An automaton class is usually defined to assist in generating code for
# parsing the recognized strings.  With FiniteAutomaton this is accomplished
# through code generators.  Each code generator is a module that defines the
# logic for examining the automaton information and producing code in a
# particular language.
#
# The quick-and-dirty approach is to extend your automaton definition class
# with a code generator.  The extend_with method is syntactic sugar to help
# with this.  E.g.
#   class MyAutomaton < FiniteAutomaton
#     extend_with CxxParserGenerator
#
#     .
#     .
#     .
#   end
# In this case, action definitions usually return a string giving the code to
# place in the generated parser to be executed when a transition involving
# that action is made.
#
# The more general solution, which allows multiple code generating classes to
# share the same automaton definition, is to derive a class from FiniteAutomaton
# to define the automaton and then, from that class, derive a class for each
# generator. E.g.
#   class MyAutomaton < FiniteAutomaton
#     .
#     .
#     .
#   end
#
#   class MyCxxParserGenerator < MyAutomaton
#     extend_with CxxParserGenerator
#
#     .
#     .
#     .
#   end
#
class FairCG::FiniteAutomaton
  class Action
    def initialize(name, order_key, options, block)
      @name = name
      @order_key = order_key
      @code_generator = block
      @options = options
    end
    
    attr_reader :name, :order_key, :options
    
    # Called by code generators to obtain the code the generated parser should
    # execute to implement this action.  _context_ will typically be the class
    # object for the parser generator.
    #
    # The behavior of this method depends on whether a block was given for the
    # action definition.  If a block was given, it is executed now using
    # Object#instance_eval on _context_.  If no block was given then the method
    # action_code is invoked on _context_.  Depending on the definition of
    # action_code, either one or two arguments will be passed.  The first
    # argument is always the name of the action.  The second argument (if
    # action_code accepts a second, non-optional argument) is the options hash
    # passed to the action definition.  This is just a convenience, as the
    # options hash can be accessed through machine_def.actions[name].options.
    def code(context)
      if @code_generator
        context.instance_eval(&@code_generator)
      else
        m = context.method(:action_code)
        args = [name]
        args << options if m.arity >= 2
        m.call(*args)
      end
    end
  end
  
  class State
    # Used to capture the actions (called as methods) for a transition
    class TransitionCapture
      def initialize(parser)
        @parser = parser
        @min_order_key = 0
        @actions = []
      end
      
      def actions
        @actions.dup
      end
      
      # Implements action capture and order validation
      def method_missing(name)
        action = @parser.actions[name]
        raise("#{name} not a defined action") unless action
        raise("#{name} out of order") unless action.order_key >= @min_order_key
        @actions << name
        @min_order_key = action.order_key + 1
      end
      
      def self.gather_actions(parser, block)
        return [] unless block
        
        capture = TransitionCapture.new(parser)
        capture.instance_eval(&block)
        return capture.actions
      end
    end
    
    Transition = Struct.new(:end_state, :actions)
    
    @@to_error = Transition.new(:error, [])
    
    def initialize(parser, name, final)
      @parser = parser
      @name = name
      @final = final
      @transitions = {}
    end
    
    attr_reader :final
    
    # Returns the transitions for this State
    def transitions
      @transitions
    end
    
    def default_transition?
      @default_transition || @parser.default_transition
    end
    
    def self.range_string(first, last)
      (first..last).inject("") {|a,i| a << i}
    end
    
    def self.expand_string_condition(chars)
      chars.gsub(/(.)-(.)/) {|m| range_string($1, $2)}
    end
    
    # Defines a transition from one state to another in an automaton.
    #
    # The _rule_ is a hash with a single entry.  The key of this entry gives
    # the input characters that indicate this transition and the value of the
    # entry is the name of the state that results from the transition.  The set
    # of input characters may span multiple character classes; the
    # FiniteAutomaton class works out a partition of the character set that
    # satisfies all of the transitions in the entire automaton.  Any given
    # character may only indicate one transition; this constraint is checked
    # and an exception will be raised when the class is loaded if it is
    # violated.  The symbol <tt>:default</tt> may be passed as the key of 
    # _rule_ to define a state's default transition.
    #
    # The block, if given, defines the actions to be taken for this transition.
    # Use the name of a defined action as a method call in the block to include
    # the action in the transition.  This is implemented through
    # TransitionCapture#method_missing.  E.g.
    #   transition "0-9" => :int_part do
    #     accumulate_integer_part
    #   end
    # Multiple actions must be given in the order they are defined for the
    # automaton; an exception will be raised when the class is loaded if this
    # constraint is violated.
    def transition(rule, &block)
      @parser.reset_caches
      raise "Invalid transition syntax" if rule.length != 1
      
      def check_for_overload(chars)
        intersect = []
        @transitions.keys.each do |k|
          intersect |= k.select {|c| chars.include?(c)}
        end
        raise("Transitions overloaded for %s in %s" % [FairCG::Charset.inspect_chars(intersect), @name]) unless intersect.empty?
      end
      
      condition = rule.keys[0]
      save = case condition
      when :default
        raise "Default transition already defined" if @default_transition
        proc {|trans| @default_transition = trans}
      when String
        condition = self.class.expand_string_condition(condition)
        chars = condition.chars.collect {|c| FairCG::Charset.decode_char(c)}
        check_for_overload(chars)
        proc {|trans| @transitions[chars] = trans}
      when Range
        raise("Ranges must indicate integer values") unless condition.minmax.all? {|c| c.is_a? Integer}
        check_for_overload(condition)
        chars = condition.to_a
        proc {|trans| @transitions[chars] = trans}
      end
      end_state = rule.values[0]
      save[Transition.new(
        end_state,
        TransitionCapture.gather_actions(@parser, block)
      )]
    end
    
    # Get the Transition object corresponding to a particular input character
    def transition_for(char)
      (@transitions[@transitions.keys.find {|k| k.include?(char)}] unless char == :other) ||
        @default_transition || @parser.default_transition || @@to_error
    end
  end
  
  class << self
    # Discards the cached ordering information, usually used internally when
    # the automaton definition changes
    def reset_caches
      @state_names = nil
      @char_classes = nil
    end
    
    # Syntactic sugar, usually used to turn an automaton into a code generator.
    # E.g.
    #   extend_with CxxParserGenerator
    def extend_with(*args)
      extend(*args)
    end
    
    # Define an action.  _name_ should give a symbol that names the action.
    # _options_ gets attached to the action for use either by code generators
    # or by action_code (see the "Defining Actions" section).
    #
    # _name_ should be selected to avoid conflicts with the defined methods of
    # the TransitionCapture class; i.e. :send would be a bad choice for
    # _name_.
    def action(name, options = {}, &block)
      @actions ||= {}
      raise("Action #{name} defined multiple times") if @actions.has_key?(name)
      @actions[name] = Action.new(name, @actions.length, options, block)
    end
    
    # Retrieve a hash of action names to Action objects.
    def actions
      @actions || {}
    end
    
    # Retrieve the Action objects in the order the actions were defined.
    def actions_in_order
      actions.values.sort {|a, b| a.order_key <=> b.order_key}
    end
    
    # Defines the implicit default transition for the whole parser.  This
    # transition takes place on all input for which neither:
    # - an explicit transition has been declared in the current state
    # - a default transition has been declared in the current state
    #
    # This works much like a call to <tt>transition :default =></tt> in the
    # block given to state; the block given to default_transition_to defines
    # the actions to be taken in this default transition.  See State#transition
    # for more information.
    #
    # If this is not specified the parser will behave as if it were specified
    # as <tt>default_transition_to(:error) {}</tt>.
    def default_transition_to(sname, &block)
      raise "Parser default transition already defined" if @default_transition
      @default_transition = State::Transition.new(
        sname,
        State::TransitionCapture.gather_actions(self, block)
      )
    end
    
    attr_reader :default_transition
    
    # Define a state in the machine.
    #
    # _name_ should be a symbol naming the state.  The state <tt>:error</tt>
    # is a special state name used as the state resulting from a default (i.e.
    # unspecified) transition.
    #
    # _options_ may include the <tt>:final</tt> option to indicate whether a
    # state is an acceptable final state for the automaton.  By default, this
    # option is false.
    #
    # The block for this method, if given, defines the transitions from this
    # state.  See State#transition for more details.
    def state(name, options = {}, &block)
      reset_caches
      @machine_def = true
      @states ||= {}
      if @states[name]
        raise "State #{name} redefined"
      end
      result = State.new(self, name, options[:final])
      @states[name] = result
      @start_state ||= name
      result.instance_eval(&block) if block
    end
    
    # Return the names of all defined states.
    def state_names
      @state_names ||= (@states || {}).keys
    end
    
    # Return the name of the start state.
    def start_state
      @start_state
    end
    
    # Return the State object for the state _name_
    def state_info(name)
      (@states || {})[name]
    end
    
    # Return the character classes as an array of arrays of character values.
    def character_classes
      return @char_classes if @char_classes
      classes = []
      (@states || {}).values.each do |s|
        s.transitions.keys.each do |tchars|
          tchars = tchars.sort
          case
          when (classes.flatten & tchars).empty?
            classes << tchars
          when classes.include?(tchars)
            # Do nothing
          when containing_class = classes.find {|c| c & tchars == tchars}
            classes = classes - [containing_class] + [tchars, containing_class - tchars]
          else
            split_classes = []
            # Remove all characters from tchars that fall in classes entirely
            # contained by tchars
            classes.each do |c|
              if (c & tchars) == c
                tchars -= c
              end
            end
            # Determine which preexisting classes must be split
            classes.each do |c|
              if !(c & tchars).empty?
                split_classes << c
              end
            end
            # Split those classes
            split_classes.each do |c|
              classes -= [c]
              classes += [c - tchars]
            end
            classes << tchars unless tchars.empty?
          end
        end
      end
      return (@char_classes = classes)
    end
    
    def transition?(sname, ch)
      trans = state_info(sname).transition_for(ch)
      [trans.end_state, trans.actions]
    end
    
    # Return a reference to the class that contains the definition of an
    # automaton.  The returned class is either this class or the first
    # ancestor class to define an automaton.
    def machine_def
      @machine_def ? self : superclass.machine_def
    end
  end
end

module FairCG::Charset
  def self.decode_char(c)
    case $KCODE
    when /u/io
      l, *t = c.bytes.to_a
      indicated_t_count = case l
      when 0x00..0x7F then return l
      when 0xC2..0xDF then 1
      when 0xE0..0xEF then 2
      when 0xF0..0xF7 then 3
      else
        raise("Invalid lead byte in UTF-8 byte sequence")
      end
      raise("Invalid UTF-8 trailing byte count") unless t.length == indicated_t_count
      t.inject(l & (0xFF >> (t.length + 1))) {|r, tb| (r << 6) | (tb & 0x3F)}
    when /n/io
      raise("String broke to invalid character sequence") if c.length > 1
      return c[0]
    else
      raise("Unsupported character encoding")
    end
  end
  
  def self.inspect_chars(chars)
    dchars = ""
    uchars = []
    chars.each do |c|
      case $KCODE
      when /u/io
        case c
        when 0x00..0x7F
          dchars << c
        when 0x80..0x7FF
          dchars << (0xC0 | (c >> 6)) << (0x80 | (c & 0x3F))
        when 0x800..0xFFFF
          dchars << (0xE0 | (c >> 12))
          c &= 0xFFF
          dchars << (0x80 | (c >> 6))
          dchars << (0x80 | (c & 0x3F))
        when 0x10000..0x10FFFF
          dchars << (0xF0 | (c >> 18))
          c &= 0x3FFFF
          dchars << (0x80 | (c >> 12))
          c &= 0xFFF
          dchars << (0x80 | (c >> 6))
          dchars << (0x80 | (c & 0x3F))
        else
          uchars << c
        end
      when /n/io
        if (0..0xFF).include?(c)
          dchars << c
        else
          uchars << c
        end
      else
        raise("Unsupported character encoding")
      end
    end
    
    dchars = compress(dchars)
    
    case
    when uchars.empty?
      return dchars.inspect
    when dchars.empty?
      return uchars.inspect
    else
      return %Q{%p + %p} %[dchars, uchars]
    end
  end
  
  def self.compress(s)
    if add_dash = s.include?('-')
      s.gsub!('-', '')
    end
    
    r = ""
    last = nil
    rcnt = 0
    for c in s.each_char
      case
      when !last
        r << c
        rcnt = 1
      when is_succ(c, last)
        rcnt += 1
      else
        if rcnt == 2
          r << last
        elsif rcnt > 2
          r << "-" << last
        end
        r << c
        rcnt = 1
      end
      last = c
    end
    if rcnt == 2
      r << last
    elsif rcnt > 2
      r << "-" << last
    end
    
    r << '-' if add_dash
    
    return r
  end
  
  def self.is_succ(t, s)
    (t[0..-2] == s[0..-2]) && (t[-1] == s[-1] + 1)
  end
end

# Load parser generators
[
  'cxx_parser_generator.rb',
].each do |f|
  load File.join(File.dirname(__FILE__), 'fair_cg', f)
end
