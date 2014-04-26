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

require "shellwords"

module FairCG; end

module FairCG::QEscString
  def q_escaped!(value = true)
    @q_escaped = value
    self
  end
  
  def q_escaped?
    @q_escaped
  end
  
  def self.make(s)
    s.extend(self)
    s.q_escaped!
  end
end

# Extending an automaton class with this module allows generation of _dot_ tool
# (from the graphviz toolset) diagram descriptions.  If _dot_ is installed,
# this module can invoke it to generate an image as output.  See the
# generate_to method for details of output generation.
module FairCG::DotDiagramGenerator
  class OutputGenerator
    def initialize(io)
      @out = io
      @indent = 1
    end
    
    def io
      @out
    end
    
    def q_esc(s)
      FairCG::DotDiagramGenerator.q_esc(s)
    end
    
    def dot_att_str(attrs)
      FairCG::DotDiagramGenerator.dot_att_str(attrs)
    end
    
    # Declare a state or, if it has already been declared, set additional
    # attributes on it.  The state will be declared in the graph or subgraph
    # in which it appears if this is the first mention of the state.
    def state(sname, attrs = {})
      attrs = dot_att_str(attrs)
      attrs = " [#{attrs}]" unless attrs.empty?
      @out.puts(istr + %Q{"#{q_esc(sname)}"#{attrs}})
    end
    
    # Declare a subgraph and set its attributes.  The <tt>:id</tt> attribute
    # sets the ID of the subgraph and the <tt>:node_defaults</tt> attribute
    # sets the default attributes for nodes in this subgraph.  All other
    # attributes are set as name=value pairs in the subgraph.
    def subgraph(attrs = {}, &block)
      attrs = attrs.dup
      id = attrs.delete(:id)
      node_defaults = attrs.delete(:node_defaults) || {}
      @out.puts(istr + "subgraph #{id} {")
      indent do
        attrs.each_pair do |k,v|
          @out.puts(istr + %Q{#{k} = "#{q_esc(v)}"})
        end
        node_defaults = dot_att_str(node_defaults)
        @out.puts(istr + %Q{node [#{node_defaults}]}) unless node_defaults.empty?
        block.call
      end
      @out.puts(istr + "}")
    end
    
    def istr
      "  " * @indent
    end
    
    def indent
      @indent += 1
      begin
        yield
      ensure
        @indent -= 1
      end
    end
  end
  
  def self.q_esc(s)
    return s if s.is_a?(FairCG::QEscString) && s.q_escaped?
    FairCG::QEscString.make(s.to_s.gsub(/(?=["\\])/,'\\'))
  end
  
  def q_esc(s)
    FairCG::DotDiagramGenerator.q_esc(s)
  end
  
  if ENV["OS"] =~ /Windows/
    def shell_join(cmd)
      cmd.collect do |t|
        case t
        when :stdout_to
          '>'
        when :add_stdout_to
          '>>'
        when :stderr_to
          '2>'
        when :add_stderr_to
          '2>>'
        when :piped_to
          '|'
        when :and_then
          '&'
        when :and_if_successful
          '&&'
        when :and_if_failed
          '||'
        when :start_group
          '('
        when :end_group
          ')'
        else
          t = t.dup
          t.gsub!(/(?=[|&<>^()])/, '^')
          (t =~ /\s/ ? %Q{"#{t}"} : t)
        end
      end.join(' ')
    end
  else
    def shell_join(cmd)
      Shellwords.join(cmd)
    end
  end
  
  # Generates output from the defined finite automaton.
  #
  # If _out_ is a String it will be treated as the name of a file to be
  # generated.  Unless specified through the <tt>:format</tt> option, the
  # output format will be inferred from the extension of the file name.  When
  # _out_ is not a String it is treated as an IO object to receive the dot
  # diagram description.
  #
  # Several options are available for controlling the format of the output
  # graph:
  # [:format]  Defines the format of the file to be generated.  Only used if
  #            _out_ is a String.
  # [:layout]  Explicitly specify the layout engine to use.  Only used if _out_
  #            is a String.
  #
  # The additional_graph_info and state_attributes methods may be overridden
  # for additional control over the generated graph description.
  def generate_to(out, options = {})
    if out.is_a?(String)
      format = options[:format] || File.extname(out)[1..-1]
      cmd = ["dot", "-o#{out}"]
      cmd << "-T#{format}" if format
      cmd << "-K#{options[:layout]}" if options[:layout]
      IO.popen(shell_join(cmd), 'w') do |pipe|
        return generate_to(pipe, options)
      end
    end
    
    def make_edge(sfrom, keys, trans)
      atts = {:label=>edge_label(keys, trans.actions)}.merge(
        edge_attributes(sfrom, trans.end_state, keys)
      )
      atts = dot_att_str(atts)
      %Q{  "#{q_esc(sfrom)}" -> "#{q_esc(trans.end_state)}" [#{atts}]}
    end
    
    out.puts "digraph {"
    graph_attributes.each_pair do |k,v|
      out.puts %Q{  #{k}="#{q_esc(v)}"}
    end
    default_node_atts = dot_att_str(node_defaults)
    out.puts "  node [#{default_node_atts}]"
    default_edge_atts = dot_att_str(edge_defaults)
    out.puts "  edge [#{default_edge_atts}]" unless default_edge_atts.empty?
    additional_graph_info(OutputGenerator.new(out))
    out.puts %Q{  graph_hidden_start_node [style = invis, label = ""]}
    machine_def.state_names.each do |sname|
      sinfo = machine_def.state_info(sname)
      node_atts = {}
      if sinfo.final
        node_atts = final_node_attributes
      end
      node_atts = state_attributes(sname, node_atts)
      node_atts = (dot_att_str(node_atts) unless node_atts.empty?)
      out.puts %Q{  "#{q_esc(sname)}" [#{node_atts}]} if node_atts
      sinfo.transitions.each_pair do |keys, result|
        out.puts(make_edge(sname, keys, result))
      end
      if sinfo.default_transition?
        default_trans = sinfo.transition_for(:other)
        out.puts(make_edge(sname, :default, default_trans))
      end
    end
    out.puts %Q{  graph_hidden_start_node -> "#{q_esc(machine_def.start_state)}" [arrowhead = open, arrowsize = 3]}
    out.puts "}"
  end
  
  # Returns the attributes set as name=value pairs in the main graph.
  def graph_attributes
    {:rankdir => "LR"}
  end
  
  # Returns the default attributes set on nodes in the main graph
  def node_defaults
    {:shape=>'circle'}
  end
  
  # Returns the attributes set on nodes (states) marked as "final."
  def final_node_attributes
    {:shape=>'doublecircle'}
  end
  
  # Returns the default attributes set on edges (transitions).
  def edge_defaults
    {}
  end
  
  # Allows an opportunity to add more information to the graph output before
  # any nodes are introduced.  This enables, among other possibilities,
  # clustering nodes or grouping nodes into subgraphs.
  #
  # This method receives an OutputGenerator instance as the _diagram_
  # argument.
  def additional_graph_info(diagram)
  end
  
  # Returns the set of attributes that should be applied to the indicated
  # state node.  _attrs_ is the set of attributes computed for _state_
  # by the generation algorithm.
  def state_attributes(state, attrs)
    attrs
  end
  
  # Computes the label for a transition from the input triggers (_keys_) and
  # _actions_ to be taken.
  def edge_label(keys, actions)
    keys_desc = case keys
    when :default
      "other"
    else
      FairCG::Charset.inspect_chars(keys)
    end
    actions_desc = actions.join(', ')
    FairCG::QEscString.make(
      [keys_desc, actions_desc].collect {|i| q_esc(i)}.join('\n')
    )
  end
  
  # Computes the edge attributes from state _s_from_ to _s_to_ when
  # transitioning because of one of _keys_.  The result is merged into a Hash
  # that contains the lable computed by edge_label (which is overridden by any
  # label specified by this method).
  def edge_attributes(s_from, s_to, keys)
    {}
  end
  
  def dot_att_str(attrs)
    FairCG::DotDiagramGenerator.dot_att_str(attrs)
  end
  
  # Builds a _dot_ style attribute string from a Hash.
  def self.dot_att_str(attrs)
    attrs.collect do |k,v|
      %Q{%s = "%s"} % [k, q_esc(v)]
    end.join(', ')
  end
end
