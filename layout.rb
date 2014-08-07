#!/usr/bin/env ruby

require './diffeq'

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

    # Now all we have to do is factor everything
    { :terms => terms,
      :mults => mults,
      :ints => ints }
  end

  def self.script(input, quiet=false)
    conn = Connections.new(input, quiet)
    p conn.instance_eval {@diffeq}
    results = conn.connect
    p results
    p Layout.new.layout(results)
  end
end

script(Layout, true) if __FILE__ == $0
