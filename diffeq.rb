#!/usr/bin/env ruby

# Error handling
def error(msg, code, backtrace=false)
  $stderr.puts("ERROR: #{msg}")
  $stderr.puts caller if backtrace
  exit(code)
end

# Just like array
class Hash
  def compact
    self.delete_if {|k, v| v.nil?}
  end
end

# Some helper methods to make code a bit nicer
class Array
  def sum(init=0)
    self.inject(init) {|sum, obj| sum + (block_given? ? yield(obj) : obj)}
  end

  def product(init=1)
    self.inject(init) {|prod, obj| prod * (block_given? ? yield(obj) : obj)}
  end

  def dup
    self.map {|i| i}
  end
end

# Some basic methods for the general work flow
# We represent a parsing as an array:
#   [ [symbol, *data], ..., [symbol, *data] ]
class Array
  # Add the given token(s) to the end of the array
  # If token is just a symbol, add it by itself
  # If it is an empty array then ignore it
  # If it is an array starting with a symbol, add it as the last element
  # Otherwise concatenate it to the end (it should be an array of tokens)
  def addToken(token)
    return if token.nil?
    if token.is_a?(Symbol)
      self << [token]
    elsif token.is_a?(Array) then
      if token.empty? then
        # do nothing
      elsif token[0].is_a?(Symbol) then
        self << token
      else
        self.concat(token)
      end
    else
      error("Unknown token type for #{token.inspect}", -1, true)
    end
  end

  # Scan the token sequence for any run of target symbols and transform
  # them with the given block
  def consume(*targets)
    diffeq = self.dup
    transformed = []
    while !diffeq.empty?
      stack = diffeq.take_while {|t| targets.include?(t[0])}
      diffeq = diffeq.drop_while {|t| targets.include?(t[0])}
      transformed.addToken(stack.empty? ? diffeq.shift : yield(stack))
    end
    transformed
  end

  # Targets should be an array of arrays of symbols; so like
  #    [ [sym_1_1, sym_1_2, ...], [sym_2_1, sym_2_2, ...] ... ]
  # Demand that the token sequence be a sequence formed by elements
  # of the first group followed by the second, and so on. Then transform
  # collections matching one item from each group with the given block
  def combine(*targets)
    error("Combine cannot have empty target set", -1) if targets.empty?
    diffeq = self.dup
    transformed = []
    while !diffeq.empty?
      i = 1
      form = targets.map {|t|
        unless t.include?(diffeq[0][0]) then
          error("Cannot match the #{i}th combination target #{t.inspect}", -1)
        end
        i += 1
        diffeq.shift
      }
      transformed.addToken(yield(form))
    end
    transformed
  end

  # Iterate over the token sequence; map anything matching a symbol in toks
  # and don't map anything else
  def translate(*toks)
    transformed = []
    self.each {|t|
      transformed.addToken(toks.include?(t[0]) ? yield(t) : t)
    }
    transformed
  end

  # Find all tokens in the sequence that match the symbols in targets
  def gather(*targets)
    self.select {|t| targets.include?(t[0])}
  end

  # Find the first of targets, but make sure there aren't too many
  def request(*targets)
    items = gather(*targets)
    error("Requested #{targets.inspect}; found too many in #{self.inspect}", -1) if items.length > 1
    return (items.empty?) ? nil : items[0]
  end

  # Find the first of targets, ensure there is exactly one
  def demand(*targets)
    item = request(*targets)
    error("Demanded #{targets.inspect} but found none in #{self.inspect}", -1) if item.nil?
    return item
  end

  # Return whether the given tokens don't even appear
  def hasNone?(*targets)
    return gather(*targets).empty?
  end

  # Return whether the given tokens do appear
  def hasTokens?(*targets)
    return !hasNone?(*targets)
  end
end

class String
  def tokenize
    self.chomp.strip.split("").map {|c|
      case c
        when /^[ _,]$/
          nil
        when /^\d$/
          [:digit, c.to_i]
        when 'y'
          [:y]
        when 'x'
          [:x]
        when '\''
          [:prime]
        when '+'
          [:plus]
        when '-'
          [:minus]
        when '.'
          [:dot]
        when '='
          [:equals]
        when '*'
          nil # multiplication is concatenation, but allow this, too
        else
          error("Cannot handle character `#{c}' (#{c[0]})", -1)
      end
    }.compact
  end
end

class Numeric
  def niceDiv(divisor)
    if self.is_a?(Integer) && divisor.is_a?(Integer) && self % divisor == 0 then
      self / divisor
    else
      self / divisor.to_f
    end
  end
end

# Tokens will always be held in arrays
class Array
  def prohibitX
    error("Currently does not support using x", -1) if hasTokens?(:x)
    self
  end

  def parseNumbers
    self.consume(:digit, :dot) {|stack|
      stack.unshift [:digit, 0]
      num = stack.map {|tok|
        tok[0] == :digit ? tok[1] : '.'
      }.join("").gsub(/^0+\d/) {|str| str[-1].chr}
      error("#{num} has too many decimal points", -1) if num.scan(/\./).length > 1
      [:num, num.include?('.') ? num.to_f : num.to_i]
    }
  end

  def parseSigns
    # We allow double, triple, etc negation (or posation?)
    self.consume(:plus, :minus) {|stack|
      stack.gather(:minus).length % 2 == 0 ? :plus : :minus
    }
  end

  def checkPrimes
    lastNP = nil

    self.each {|tok|
      if tok[0] == :prime && lastNP != :y then
        error("Prime mark does not exclusively follow y in the given equation.", -1)
      end
      lastNP = tok[0] unless tok[0] == :prime
    }
    self
  end

  def sides
    equals = self.request(:equals)
    return [self, [[:num, 0]]] if equals.nil?
    left = self.take_while {|t| t[0] != :equals}
    right = self.drop_while {|t| t[0] != :equals}
    right.shift

    [left, right]
  end

  # Get zero on the RHS
  def balanceToZero
    left, right = *sides
    error("Equals empty on one side", -1) if left.empty? || right.empty?
    error("Equation has side with just signs", -1) if [left, right].any? {|a| a.hasNone?(:x, :y, :num)}

    right.unshift [:plus]
    left + right.parseSigns.translate(:plus, :minus) {|token|
      (token[0] == :plus) ? :minus : :plus
    }
  end

  def parsePrimes
    self.consume(:prime) {|stack|
      [:derivative, stack.length]
    }.consume(:y, :derivative) {|stack|
      derivatives = []
      while !stack.empty?
        item = stack.shift
        if item[0] == :y then
          derivatives << [:derivative, 0]
        else
          derivatives[-1][-1] += item[-1]
        end
      end
      derivatives
    }
  end

  def parseCoefs
    self.consume(:x, :derivative, :num) {|stack|
      coef = stack.gather(:num).product {|n, d| d}
      stack.gather(:x, :derivative).unshift [:num, coef]
    }
  end

  def parseTerms
    unsigned = self.consume(:x, :derivative, :num) {|stack|
      coef = stack.demand(:num)
      term = stack.gather(:x, :derivative)
      [:term, coef[1], *term]
    }
    unsigned.unshift [:plus]
    unsigned.parseSigns.combine([:plus, :minus], [:term]) {|sign, term|
      term[1] *= -1 if sign[0] == :minus
      term
    }
  end

  def combineTerms
    self.map {|sym, coef, *factors|
      xs = factors.gather(:x).length
      orders = factors.gather(:derivative).map {|d| d[-1]}.sort.reverse
      [coef, xs, orders]
    }.inject(Hash.new) {|h, (coef, xs, orders)|
      key = [xs, *orders]
      h[key] ||= 0
      h[key] += coef
      h
    }.map {|(xs, *orders), coef|
      [:term, coef, [:x, xs], [:derivatives, *orders]]
    }.sort_by {|sym, coef, (x, xs), (d, *orders)|
      [orders.max || 0, orders.sum, orders.length, xs, *orders]
    }.reverse
  end

  def dropZeroes
    self.reject {|d| [0, 0.0].include?(d[1])}
  end

  def normalize
    return self if self.any? {|sym, coef, (x, xs), (d, *orders)| xs > 0 || orders.empty?}
    lowest = self.map {|sym, coef, (x, xs), (d, *orders)| orders.min}.min
    self.map {|sym, coef, (x, xs), (d, *orders)|
      [sym, coef, [x, xs], [d, *orders.map {|order| order - lowest}]]
    }
  end

  def monic
    # We need to demand that the high order term is a monomial
    highest = self.map {|sym, coef, (x, xs), (d, *orders)| orders.max || 0}.max || 0
    badprod = self.any? {|sym, coef, (x, xs), (d, *orders)|
      orders.include?(highest) && orders.length > 1 || xs > 0
    }
    error("Cannot have highest order term with multiple factors", -1) if badprod
    factor = self[0][1] # This should be the highest coefficient
    self.map {|sym, coef, x, orders|
      [sym, coef.niceDiv(factor), x, orders]
    }
  end

  def asEquation
    sym, coef, (x, xs), (d, *orders) = *self[0]
    if orders.empty? then
      self + [[:equals], [:term, 0, [:x, 0], [:derivative]]]
    else
      left = [self[0]]
      right = self[1...(self.length)].map {|sym, coef, x, orders| [sym, coef * -1, x, orders]}
      right << [:term, 0, [:x, 0], [:derivatives]] if right.empty?
      left + [[:equals]] + right
    end
  end

  def show(str)
    $stdout.puts(str + " " + self.map {|t| t.inspect}.join("; "))
    self
  end
end

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

    adjlist = arr.inject(Hash.new) {|h, order|
      h[[order]] = Hash.new
      h[[order]][[order - 1]] = 1 unless order == 0
      h
    }

    if @diffeq.include?(:hash) then
      keys = @diffeq[:hash].keys.sort_by {|xs, *order| order.length}

      keys.each {|key|
        xs, *order = *key
        order.each {|factor|
          adjlist[[factor]][order] = 1
        } unless order.length == 1
      }

      keys.each {|key|
        xs, *order = *key
        adjlist[order] ||= Hash.new
        error("Somehow edge from #{order} to #{result} exists already. x's allowed?", -1) if adjlist[order].include?([result])
        adjlist[order][[result]] = @diffeq[:hash][key]
      }
    end

    adjlist = {
      :constant => @diffeq[:constant],
      :result => result,
      :adjlist => adjlist
    }
  end

  def self.script(input, quiet=false)
    conn = Connections.new(input, quiet)
    p conn.instance_eval {@diffeq}
    p conn.connect
  end
end

def readDiffEq
  $stdout.print("Please enter a differential equation to compile: ") if $stdin.tty?
  diffeq = $stdin.gets.chomp.strip
  error("Empty differential equation; terminating.", -1) if diffeq =~ /^\s*$/
  diffeq
end

def script(klass, *args, &block)
  klass.script(readDiffEq, *args, &block)
end


#script(Tokens, true)
script(Connections, true)
