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

class Node
  @@fans = Hash.new

  def self.fans(destination, *sources)
    sources.each {|src|
      (@@fans[src] ||= Hash.new(0))[destination] += 1
    }
  end

  def self.table
    @@fans
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
  @@products = Hash.new

  def self.table
    @@table
  end
  def self.products
    @@products
  end

  def self.times(left, right, product=nil)
    return @@products[product] if !product.nil? && @@products.include?(product)

    node = Hash.node(:mul => @@count)
    record = {:left => left, :right => right}
    if product then
      record.update(:product => product)
      @@products[product] = node
    end
    @@table[@@count] = record
    @@count += 1

    Node.fans(node, left, right)
    node
  end
end

class Add
  @@count = 0
  @@table = Hash.new

  def self.table
    @@table
  end

  def self.add(*terms)
    terms.flatten!
    terms.compact!
    return terms[0] if terms.length == 1

    node = Hash.node(:add => @@count)
    @@table[@@count] = {:terms => terms}
    @@count += 1

    Node.fans(node, *terms)
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
    term_map = Proc.new {|term|
      product = [term.shift, term.shift].sort
      update = Proc.new {|left, right| Mul.times(left, right, product.dup)}
      node = update[Var.var(product[0]), Var.var(product[1])]
      node = update[Var.var(product.insort(term.shift)), node] until term.empty?
      node
    }
    return Add.add(single, self[:product].map {|term| term_map[term.dup]}) if self.alive?

    other, with, factor = self[:other].node, self[:across].node, Var.var(self[:factor])
    return Add.add(single, Mul.times(factor, with), other)
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
    singles = Var.vars(*terms.map {|src, w| src}.select {|src| src.length == 1})
    node = factors.node
    prods = Hash.new
    Layout.prodmap(factors, prods)

    if node[:type] == :add then
      # Since we construct nodes from a maximal factoring, we only have to worry
      # about this kind of thing here--every where else, there won't be adjacent
      # adds and such in the heirarchy, and single vars get added at the base.
      Add.table[node[:ref]][:terms] += singles
      Node.fans(node, *singles)
    else
      node = Add.create(singles, node)
    end

    # Now all we have to do is factor everything
    { :terms => terms,      # Terms that get added to the result
      :mults => mults,      # Anything that has things multipied together: [src, dst, weight]1
      :ints => ints,        # Integrations
      :factors => factors,  # Factor hashses (see #factor above)
      :singles => singles,
      :node => node,
      :state => {
        :mul => Mul.table,
        :add => Add.table,
        :products => Mul.products,
        :fans => Node.table,
      },
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
