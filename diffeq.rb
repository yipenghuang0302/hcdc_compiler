#!/usr/bin/env ruby

require './base'
require './tokenops'

require 'pp'

class Tokens
  @toks, @parsed, @quiet = [], false, false
  def initialize(arr)
    @toks = arr
  end

  def tokens
    @toks
  end

  def quiet=(bool)
    @quiet = bool
  end

  def quiet
    @quiet
  end

  def showResult(string)
    $stdout.puts ""
    @toks.show(string)
    self
  end

  def method_missing(meth, *args, &block)
    string = args.shift
    @toks = @toks.send(meth, *args, &block) unless meth == :show
    showResult(string) unless @quiet
    self
  end

  def parse!
    return nil if @parsed
    @parsed = true
    self.show("Tokens are")
        .prohibitX("Checking that x is not present")
        .parseNumbers("With numbers parsed")
        .parseSigns("With signs parsed")
        .checkPrimes("With primes validated")
        .balanceToZero("All terms on the left")
        .parsePrimes("With primes parsed")
        .parseCoefs("With coefficients parsed")
        .parseTerms("With terms parsed")
        .combineTerms("With terms combined")
        .dropZeroes("Without zero coefs")
        .normalize("Normalizing so that y is lowest order term")
        .monic("Monic")
        .asEquation("As an equation")
    return self
  end

  def to_hash
    term_to_hash = proc {|sym, coef, (x, xs), (d, *orders)|
      { :coef => coef,
        :xs => xs,
        :orders => orders }
    }
    parse! unless @parsed
    left, right = @toks.sides
    left.map!(&term_to_hash)
    right.map!(&term_to_hash)

    error("LHS should be exactly one term") if left.length != 1
    error("LHS should not have x factor") if left[0][:xs] > 0
    error("LHS should have one factor") if left[0][:orders].length > 1

    constant = right.select {|term| term[:xs] == 0 && term[:orders].empty?}
    error("RHS has more than one constant term") if constant.length > 1
    terms = right.select {|term| term[:xs] > 0 || !term[:orders].empty?}

    result = {
      :lhs => left[0],
      :constant => constant.empty? ? 0 : constant[0][:coef],
      :terms => terms.empty? ? nil : terms
    }.compact
    result[:hash] = result[:terms].inject(Hash.new) {|h, term|
      key = [term[:xs], *term[:orders]]
      h.update(key => term[:coef])
    } unless result[:terms].nil?

    result
  end

  def to_s
    return @toks.map {|t| t.inspect}.join("; ") unless @parsed

    left, right = @toks.translate(:term) {|sym, coef, (x, xs), (d, *orders)|
      xstr = (xs > 0) ? "x^#{xs}" : ""
      ystr = orders.map {|o| "y" + ("'" * o)}.join(" ")
      string = [coef, xstr, ystr].join(" ")
      [:term, string]
    }.sides.map {|side| side.map {|sym, str| str}}

    (left.join(' + ') + ' = ' + right.join(' + ')).gsub(/\s+/, " ")
  end

  def self.script(input, quiet = false)
    tokens = Tokens.new(input.tokenize)
    tokens.quiet = quiet
    tokens.parse!
    $stdout.puts(tokens.to_hash)
  end
end

class Connections
  @tokens, @diffeq = nil
  def initialize(input, quiet=false)
    @tokens = Tokens.new(input.tokenize)
    @tokens.quiet = quiet
    @tokens.parse!
    $stdout.puts @tokens.to_s
    @diffeq = @tokens.to_hash
  end

  def connect
    result = @diffeq[:lhs][:orders][0]

    arr = (0..result).to_a.reverse

    adjlist = arr.inject(Graph.new) {|h, order|
      h[[order]] = Hash.new
      h[[order]][[order - 1]] = [1] unless order == 0
      h
    }

    if @diffeq.include?(:hash) then
      keys = @diffeq[:hash].keys.sort_by {|xs, *order| order.length}

      keys.each {|key|
        xs, *order = *key
        order.each {|factor|
          (adjlist[[factor]][order] ||= []) << 1
        } unless order.length == 1
      }

      keys.each {|key|
        xs, *order = *key
        error("Somehow order #{order} already exists in graph?", -1) if order.length != 1 && adjlist.include?(order)
        adjlist[order] ||= Hash.new
        adjlist[order][[result]] = [@diffeq[:hash][key]]
      }
    end

    adjlist = {
      :constant => @diffeq[:constant],
      :result => result,
      :adjlist => adjlist
    }
  end

  def self.usage
    puts "ruby diffeq.rb"
    puts "\tNo arguments used at all"
    puts "\tIf input is not piped in, a diffeq will be requested"
  end

  def self.script(input, quiet=false)
    conn = Connections.new(input, quiet)
    puts "differential equation is: #{conn.instance_eval {@diffeq}.inspect}"
    adjlist = conn.connect
    puts "<connection-adjlist>"
    pp adjlist
    puts "</connection-adjlist>"

    return adjlist
  end
end

if __FILE__ == $0 then
  script(Connections, true)
end
