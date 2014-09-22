#!/usr/bin/env ruby

require './base'
require './diffeq'
require 'pp'
require 'set'

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

class Node
  @@fans = Hash.new

  def self.fans(destination, *sources)
    sources.flatten.each {|src|
      (@@fans[src] ||= Set.new).add(destination)
    }
  end

  def self.table
    @@fans.keys.inject(Hash.new) {|h, src|
      dsts = @@fans[src].to_a
      h[src] = dsts if src[:type] == :var || dsts.length > 1
      h
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
    return @@factors[key] if @@factors.include?(key)

    node = Hash.node(:mul => @@count)
    @@factors[key] = node
    @@table[@@count] = {:left => left, :right => right}
    @@count += 1

    Node.fans(node, left, right)
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
    return terms[0] if terms.length == 1

    key = Node.key(terms)
    return @@terms[key] if @@terms.include?(key)

    node = Hash.node(:add => @@count)
    @@terms[key] = node
    @@table[@@count] = {:terms => terms}
    @@count += 1

    Node.fans(node, terms)
    node
  end

  # Dangerous if used on anything but the final node.
  def self.append(node, *rest)
    rest.flatten!
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

    single = Var.vars(self[:single])
    term_map = Proc.new {|term| Var.vars(term).inject {|a, b| Mul.times(b, a)}}
    return Add.add(single, self[:product].map {|term| term_map[term.dup]}) if self.alive?

    other, with, factor = self[:other].node, self[:across].node, Var.var(self[:factor])
    return Add.add(single, Mul.times(factor, with), other)
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

  def self.prodmap(factors, mapping, *product)
    [*factors[:single], *(factors[:product] || [])].each {|item|
      key = (product + [item]).flatten.sort.reverse
      mapping[key] = [item, *product]
    }
    unless factors.leaf? then
      prodmap(factors[:across], mapping, factors[:factor], *product)
      prodmap(factors[:other], mapping, *product)
    end
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
    singles = Var.vars(*terms.map {|src, w| src}.select {|src| src.length == 1})
    node = Add.append(factors.node, singles)
    prods = Hash.new
    Layout.prodmap(factors, prods)

    # Now all we have to do is factor everything
    { :terms => terms,           # Terms that get added to the result
      :result => conn[:result],  # Max order needed...
      :mults => mults,           # Anything that has things multipied together: [src, dst, weight]1
      :ints => ints,             # Integrations
      :factors => factors,       # Factor hashses (see #factor above)
      :singles => singles,
      :node => node,
      :state => {
        :mul => Mul.table,
        :factors => Mul.factors,
        :add => Add.table,
        :terms => Add.terms,
        :fans => Node.table,
      },
      :prods => prods }     # `Inverse' of factor -- maps terms to factor sequence
  end

  def self.script(input, quiet=false)
    conn = Connections.new(input, quiet)
    p conn.instance_eval {@diffeq}
    results = conn.connect
    p results
    layout = Layout.layout(results)
    p layout[:factors].factoring
    pp layout
  end
end

script(Layout, true) if __FILE__ == $0
