#!/usr/bin/env ruby

require './diffeq'
## See description method below for info.

# Change keys so that if we give it args, it finds keys with those args
class Hash
  def leaf?
    self.include?(:product)
  end

  def dead?
    self.leaf? && self[:single].empty? && self[:product].empty?
  end

  def alive?
    self.leaf? && !self.dead?
  end
end

class Array
  def factor_out(item)
    with, without = self.partition {|term| term.include?(item)}
    with.map! {|term| term.delete_first(item)}
    [with, without].map {|arr| arr.factor}
  end

  def term_counts
    self.flatten.uniq.inject(Hash.new(0)) {|h, f|
      h.update(f => self.select {|term| term.include?(f)}.length)
    }
  end

  def factor
    single, multiple = self.uniq.partition {|term| term.length == 1}
    result, counts = { :single => single.flatten }, multiple.term_counts

    return result.update(:product => multiple) if (counts.values.max || 0) <= 1

    factoring = counts.keys(counts.values.max).max
    with, without = *multiple.factor_out(factoring)

    result.update(:factor => factoring, :across => with, :other => without)
  end
end

module LayoutGraph
class Node
  @@outputs = Hash.new

  def self.outputs(destination, *sources)
    sources.flatten.each {|src|
      (@@outputs[src.dup] ||= Hash.new(0))[destination.dup] += 1 # Numeric--consider squaring
    }
  end

  def self.table
    @@outputs.keys.inject(Hash.new) {|h, src|
      dsts = @@outputs[src].keys.inject([]) {|arr, dst|
        count = @@outputs[src][dst]
        count.times { arr << dst }
        arr
      }
      h.update(src => dsts)
    }
  end

  def self.key(*nodes)
    nodes.flatten!
    key = nodes.inject(:mul => [], :add => [], :var => []) {|h, node|
      h[node[:type]] << node[:ref]
      h
    }
    key.keys.each {|k| key[k].sort!}
    key
  end
end

class Var
  def self.var(var)
    Hash.node(:var => var)
  end

  def self.vars(*terms)
    terms.flatten.map {|i| Var.var(i)}
  end

  def self.integrators(max)
    max.downto(1) {|int| Node.outputs(Var.var(int-1), Var.var(int))}
  end
end

class Mul
  @@count = 0
  @@table = Hash.new
  @@factors = Hash.new

  def self.table
    @@table
  end
  def self.factors
    @@factors
  end

  def self.times(left, right)
    key = Node.key(left, right)
    return @@factors[key].dup if @@factors.include?(key)

    node = Hash.node(:mul => @@count)
    @@factors[key.dup] = node
    @@table[@@count] = {:left => left, :right => right}
    @@count += 1

    Node.outputs(node, left, right)
    node
  end
end

class Add
  @@count = 0
  @@table = Hash.new
  @@terms = Hash.new

  def self.table
    @@table
  end

  def self.terms
    @@terms
  end

  def self.add(*terms)
    terms.flatten!
    terms.compact!
    return terms[0].dup if terms.length == 1

    key = Node.key(terms)
    return @@terms[key].dup if @@terms.include?(key)

    node = Hash.node(:add => @@count)
    @@terms[key.dup] = node
    @@table[@@count] = {:terms => terms}
    @@count += 1

    Node.outputs(node, terms)
    node
  end

  # Dangerous if used on anything but the final node.
  def self.append(node, *rest)
    rest.flatten!
    return Add.add(*rest) if node.nil?
    node = node.dup
    return node if rest.empty?
    return Add.add(node, rest) unless node[:type] == :add

    ref = @@table[node[:ref]]
    old = Node.key(ref[:terms])
    ref[:terms] += rest
    new = Node.key(ref[:terms])

    @@terms.delete(old)
    @@terms[new] = node

    node
  end
end
end

class Hash
  def factoring
    singles = self[:single].map {|i| i.to_y}
    if self.leaf? then
      multiples = (self[:product] || []).map {|prod| prod.map {|i| i.to_y}.join("")}
      [singles, multiples].flatten.join(" + ")
    else
      factor = self[:factor].to_y # (self.include?(:factor) ? self[:factor].to_y : "")
      with, without = *[:across, :other].map {|sym| self[sym].factoring}
      with = "%s(%s)" % [factor, with]
      without = nil if without.empty?

      [singles, with, without].compact.flatten.join(" + ")
    end
  end

  def self.node(map)
    raise ArgumentError, "Inappropriate node map!" if map.size != 1
    k, v = *[map.keys, map.values].flatten
    {:type => k, :ref => v}
  end

  def node
    return nil if self.dead?

    single = LayoutGraph::Var.vars(self[:single])
    term_map = Proc.new {|term| LayoutGraph::Var.vars(term).inject {|a, b| LayoutGraph::Mul.times(b, a)}}
    return LayoutGraph::Add.add(single, self[:product].map {|term| term_map[term.dup]}) if self.alive?

    other, with, factor = self[:other].node, self[:across].node, LayoutGraph::Var.var(self[:factor])
    return LayoutGraph::Add.add(single, LayoutGraph::Mul.times(factor, with), other)
  end
end

class Layout
  def self.edges(adj)
    adj.keys.sort.each {|src|
      adj[src].keys.sort.each {|dst|
        adj[src][dst].each {|weight|
          yield(src, dst, weight)
        }
      }
    }
  end

  def self.parseAdjacency(adj, result)
    terms, mults, ints = [], [], []
    Layout.edges(adj) {|src, dst, weight|
      if dst == [result] then
        terms << [ src, weight ]
      elsif dst.length > 1 then
        mults << [ src, dst, weight ]
      elsif dst.length == 1 && src == [dst[0]+1] then
        error("Cannot have scaled integration", -1) if weight != 1
        ints << [ src, dst ]
      else
        error("Uncategorized edge. #{[src, dst, weight].inspect}", -1)
      end
    }
    return [terms, mults, ints]
  end

  def self.layout(conn)
    # Set up integrators -- this is required
    terms, mults, ints = *Layout.parseAdjacency(conn[:adjlist], conn[:result])
    mults.uniq!

    # These are all the y orders that come together and get multiplied
    factors = mults.map {|src, dst, weight| dst}.factor
    singles = LayoutGraph::Var.vars(*terms.map {|src, w| src}.select {|src| src.length == 1})
    node = LayoutGraph::Add.append(factors.node, singles)
    LayoutGraph::Node.outputs({:type => :var, :ref => conn[:result] - 1}, node)
    LayoutGraph::Var.integrators(conn[:result] - 1)

    # Now all we have to do is factor everything
    { :result => conn[:result],  # Max order needed...
      :factors => factors,       # Factor hashses (see #factor above)
      :node => node,
      :state => {
        :mul => LayoutGraph::Mul.table,
        :factors => LayoutGraph::Mul.factors,
        :add => LayoutGraph::Add.table,
        :terms => LayoutGraph::Add.terms,
        :outputs => LayoutGraph::Node.table,
      }
    }     # `Inverse' of factor -- maps terms to factor sequence
  end

  def self.description
    puts <<-END_DESCRIPTION
## layout.rb:
##
## This file will consume a differential equation, parse it with diffeq.rb,
## and then provide interconnection information that allows one to understand
## how to compute a solution to the equation.
##
## layout-factoring
##   This output is just a maximal factoring of all the terms in the
##   differential equation that have more than a single factor; single
##   factor terms don't play any role here at all.
##
## layout-layout
##   This output consists of several values
##     1) The order of the result (i.e. 2 if y'' = y' + y)
##     2) A description of an efficient factoring
##     3) A reference to the final `node' in the layout (i.e. the root)
##        This should be what gets sent as feedback into the system
##     4) The layout state
##
##   Factoring Description
##     This is a recursive description of a factoring. A `leaf' or terminating
##     case is a hash with only two keys--:single and :product, :single is a
##     list of terms with a single factor; :product is a list of terms that with
##     multiple factors but each factor is in exactly one term.
##
##     The recursive case has a :single key mapping to a list of terms with
##     a single factor. Then there is a key :factor, which provides the order
##     of the value being factored out. :across yields a recursive case where
##     the :factor value was found and removed; :other yields a recursive case
##     where :factor was not found.
##
##     An example may be illustrative at this point
##       Equation: y''' = 2y''y + y'y' + y'y + y''y'
##       Layout-factoring: y'(y + y' + y'') + y''y
##       Factoring Description:
##         {:single=>[],
##          :factor=>1,
##          :across=>{:single=>[0, 1, 2], :product=>[]},
##          :other=>{:single=>[], :product=>[[2, 0]]}},
##
##   Layout State, a hash with the following values:
##     :mul
##       this is a hash going from Multiplication Node ID to factors where
##       the key is the ID (integer), the value for a given key is a hash
##       with two values, :left and :right. Both point to hashes that have
##       the same form--a value key :type whose value denotes what the type
##       of the factor is (:mul, :var, :add, etc) followed by the ID of the
##       value (i.e. which add, which mul, or what order variable).
##     :factors
##       this is a map of `what gets multiplied' to node ID (i.e. something
##       that should be referenced in the :mul value above). This basically
##       is just the inverse of the above and is used so that the same exact
##       multiplication isn't used more than once.
##     :add
##       this is similar to :mul--it is a hash mapping add ID's (integers) to
##       a hash containing only one key, :terms, which maps to a list of values
##       of the form {:type => sym, :ref => ID} where sym is :mul, :add, or
##       :var and ID is the identifier for a value of the given type.
##     :terms
##       just as :factors provides an inverse for :mul, this does with :add.
##     :outputs
##       This is a hash where each key is of the form {:type => sym, :ref => ID}
##       and the values are lists of `nodes' of the same form that the given
##       keyed node will output to (i.e. everything needing it).
##
    END_DESCRIPTION
  end

  def self.usage
    puts "ruby layout.rb"
    puts "\tNo arguments used at all"
    puts "\tIf input is not piped in, a diffeq will be requested"
  end

  def self.script(input)
    layout = Layout.layout(Connections.script(input))
    self.describe
    puts "<layout-factoring>"
    pp layout[:factors].factoring
    puts "</layout-factoring>"
    puts "<layout-layout>"
    pp layout
    puts "</layout-layout>"

    return layout
  end
end

script(Layout) if __FILE__ == $0
