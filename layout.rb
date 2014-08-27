#!/usr/bin/env ruby

require './diffeq'
require 'pp'

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

  def common_factor
    counts = self.flatten.uniq.inject(Hash.new) {|h, f|
      h.update(f => self.select {|term| term.include?(f)}.length)
    }
    counts.key(counts.values.max)
  end
  
  def factor
    single, multiple = self.uniq.partition {|term| term.length == 1}
    return {
      :single => single,
      :product => multiple
    } if multiple.length <= 1 && multiple.all? {|term| term.length == 2}
    factoring = multiple.common_factor
    with, without = *multiple.factor_out(factoring)

    { :single => single.flatten,
      :factor => factoring,
      :across => with,
      :other => without }
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
      key = (product + [item]).flatten.sort
      mapping[key] = [item, *product]
    }
    if factors.include?(:factor) then
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
    pp Layout.new.layout(results)
  end
end

script(Layout, true) if __FILE__ == $0
