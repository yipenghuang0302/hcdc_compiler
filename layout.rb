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
    with, without = self.partition {|term| term.include?(max)}
    with.map! {|term| term.delete_first(max)}
    [with, without].map {|arr| arr.factor}
  end

  def common_factor
    counts = self.flatten.uniq.inject(Hash.new) {|h, f|
      h.update(f => self.select {|term| term.include?(f)}.length)
    }
    counts.key(counts.values.max)
  end
  
  def factor
    return self if self.length == 1 && self[0].length <= 2
    return self unless self.any? {|term| term.length > 2}

    single, multiple = self.uniq.partition {|term| term.length == 1}
    with, without = *multiple.factor_out(multiple.common_factor)

    { :single => single.flatten,
      :factor => max,
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

  def layout(conn)
    # Set up integrators -- this is required
    terms, mults, ints = [], [], []
    adj = conn[:adjlist]

    adj.keys.sort.each {|src|
      adj[src].keys.sort.each {|dst|
        adj[src][dst].each {|weight|
          if dst == [conn[:result]] then
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
      }
    }
    mults.uniq!

    # These are all the y orders that come together and get multiplied
    factors = mults.map {|src, dst, weight| dst}.factor

    # Now all we have to do is factor everything
    { :terms => terms,
      :mults => mults,
      :ints => ints,
      :factors => factors }
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
