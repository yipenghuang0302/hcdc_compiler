#!/usr/bin/env ruby

require './diffeq'
require 'pp'

# Change keys so that if we give it args, it finds keys with those args
class Hash
  alias_method :old_keys, :keys
  def keys(*args)
    return self.old_keys if args.empty?
    self.keys.select {|k| args.include?(self[k])}
  end

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
  def delete_first(obj)
    result = self.map {|i| i}
    idx = result.find_index(obj)
    result.delete_at(idx) unless idx.nil?
    result
  end

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

  def insort(item)
    self << item
    self.sort!
    item
  end
end

class Integer
  def to_y
    (self < 0) ? '' : ('y' + ("'" * self))
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

  def nodes(state)
    return [] if self.dead?

    return {:add =>
      self[:single].map {|i| {:int => i}} + self[:product].map {|term|
        dup, nodes, mul, product = term.map {|e| e}, [], state[:mul][:count], []

        update = Proc.new {|node|
          old, node = state[:products][product], node.update(:mul => mul, :product => product.map {|e| e})
          state[:mul][mul] = state[:products][product] = old || node
          unless old then
            (state[:fans][:int][node[:left]] ||= []) << mul
            (state[:fans][node[:type]][node[:right]] ||= []) << mul
            mul += 1
          end
          nodes << node
        }

        product = [dup.shift, dup.shift].sort
        update[{:left => product[0], :right => product[1], :type => :int}]
        update[{:left => {:int => product.insort(dup.shift)}, :right => {:mul => mul-1}, :type => :mul}] until dup.empty?
        state[:mul][:count] = mul
        nodes
      }.flatten
    } if self.alive?

    # Neither dead nor alive; clearly an abomination--but really just an internal node
    
  end
end

class Layout
  # ints: # of integrators
  # muls: # of multipliers
  # fans: # of fans
  # mscale: mul 2 vars, scale by this
  # fout: how much fanout we have
  def initialize(ints=4, muls=8, fans=8, mscale=0.5, fout=3)
    @ints = ints
    @muls = muls
    @fans = fans
    @mscale = mscale
    @fout = fout
  end

  def self.many(n)
    Layout.new(4*n, 8*n, 8*n)
  end

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

  def layout(conn)
    # Set up integrators -- this is required
    terms, mults, ints = *Layout.parseAdjacency(conn[:adjlist], conn[:result])
    mults.uniq!

    # These are all the y orders that come together and get multiplied
    factors = mults.map {|src, dst, weight| dst}.factor
    prods = Hash.new
    Layout.prodmap(factors, prods)

    # Now all we have to do is factor everything
    { :terms => terms,      # Terms that get added to the result
      :mults => mults,      # Anything that has things multipied together: [src, dst, weight]1
      :ints => ints,        # Integrations
      :factors => factors,  # Factor hashses (see #factor above)
      :prods => prods }     # `Inverse' of factor -- maps terms to factor sequence
  end

  def self.script(input, quiet=false)
    conn = Connections.new(input, quiet)
    p conn.instance_eval {@diffeq}
    results = conn.connect
    p results
    layout = Layout.new.layout(results)
    p layout[:factors].factoring
    pp layout
  end
end

script(Layout, true) if __FILE__ == $0
