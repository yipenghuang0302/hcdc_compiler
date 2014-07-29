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
    return [self, [:num, 0]] if equals.nil?
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
    }
  end

  def parseCoefs
    self.consume(:x, :y, :derivative, :num) {|stack|
      coef = stack.gather(:num).product {|n, d| d}
      stack.gather(:x, :y, :derivative).unshift [:num, coef]
    }
  end

  def checkLinear
    self.consume(:x, :y, :derivative) {|stack|
      error("Cannot have x and y (or its derivatives) multiplied together.", -1) if stack.gather(:x, :y).length > 1
    }
    self
  end

  def parseFunctions
    self.translate(:y) { [:derivative, 0] }.consume(:derivative) {|stack|
      [:derivative, stack.sum {|sym, d| d}]
    }
  end

  def parseTerms
    unsigned = self.consume(:x, :derivative, :num) {|stack|
      coef = stack.demand(:num)
      term = stack.request(:x, :derivative)
      [:term, coef[1], *(term || [:constant])]
    }
    unsigned.unshift [:plus]
    unsigned.parseSigns.combine([:plus, :minus], [:term]) {|sign, term|
      term[1] *= -1 if sign[0] == :minus
      term
    }
  end

  def combineTerms
    terms = self.inject(Hash.new) {|h, t|
      key = [:x, :constant].include?(t[2]) ? t[2] : t[3]
      h[key] ||= 0
      h[key] += t[1]
      h
    }
    keys = terms.keys.sort_by {|k|
      k.is_a?(Integer) ? -k : (k == :x) ? 1 : 2
    }
    keys.map {|k|
      data = k.is_a?(Integer) ? [:derivative, k] : [k]
      [*data, terms[k]]
    }
  end

  def dropZeroes
    self.reject {|d| d[-1] == 0 || d[-1] == 0.0}
  end

  def prohibitX
    error("Currently does not support using x", -1) if hasTokens?(:x)
    self
  end

  def normalize
    # :derivative should be all that's left besides constant now...
    lowest = self.gather(:derivative).map {|d| d[1]}.min
    self.translate(:derivative) {|d|
      d = d.dup
      d[1] -= lowest
      d
    }
  end

  def monic
    factor = self[0][-1]
    self.map {|term|
      term = term.dup
      term[-1] = term[-1].niceDiv(factor)
      term
    }
  end

  def scaled
    factors = self.map {|term| term[-1]}
    scale = [factors.min.abs, factors.max.abs].max
    self.map {|term|
      term = term.dup
      term[-1] = term[-1].niceDiv(scale)
      term
    }
  end

  def asEquation
    if [:x, :constant].include?(self[0][0]) then
      self + [[:equals], [:constant, 0]]
    else
      [self[0]] + [[:equals]] + self[1...(self.length)].map {|term|
        term = term.dup
        term[-1] *= -1
        term
      }
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
        .parseNumbers("With numbers parsed")
        .parseSigns("With signs parsed")
        .checkPrimes("With primes validated")
        .balanceToZero("All terms on the left")
        .parsePrimes("With primes parsed")
        .parseCoefs("With coefficients parsed")
        .checkLinear("Validating equation is linear")
        .parseFunctions("With functions parsed")
        .parseTerms("With terms parsed")
        .combineTerms("With terms combined")
        .dropZeroes("Without zero coefs")
        .prohibitX("Checking that x is not present")
        .normalize("Normalizing so that y is lowest order term")
        .monic("Monic")
        .asEquation("As an equation")
    return self
  end

  def to_hash
    parse! unless @parsed
    left, right = @toks.sides
    orders = right.gather(:derivative).sort_by {|d| -d[1]}

    result = {
      :lhs => left[0][1],
      :constant => (right.request(:constant) || [nil])[-1],
      :orders => orders.map {|d| d[1]}
    }.compact
    orders.each {|d| result[d[1]] = d[2]}

    result
  end

  def to_s
    return @toks.map {|t| t.inspect}.join("; ") unless @parsed

    left, right = @toks.map {|t|
      case t[0]
        when :derivative
          t[2].to_s + ' y' + ("'" * t[1])
        when :x
          t[1].to_s + ' x'
        when :constant
          t[1].to_s
        when :equals
          [:equals] # Otherwise sides won't work
      end
    }.sides

    left.join(' + ') + ' = ' + right.join(' + ')
  end

  def self.script(input, quiet = false)
    tokens = Tokens.new(input.tokenize)
    tokens.quiet = quiet
    tokens.parse!
    $stdout.puts(tokens.to_hash)
  end
end

class Layout
  @tokens, @diffeq = nil
  def initialize(input, quiet=false)
    @tokens = Tokens.new(input.tokenize)
    @tokens.quiet = quiet
    @tokens.parse!
    $stdout.puts @tokens.to_s
    @diffeq = @tokens.to_hash
  end

  def layout
    nodes, int, fan, mult = [], 1, 1, 1
    arr = (0..(@diffeq[:lhs]-1)).to_a.reverse

    arr.each_with_index {|order, i|
      node = { :int => int }
      int += 1

      # If order is defined in @diffeq then we need to copy it and send it back
      if @diffeq.include?(order) then
        node[:fan] = fan
        fan += 1
        unless @diffeq[order].to_f == 1.0 then
          node[:mult] = mult
          node[:coef] = @diffeq[order].to_f
          mult += 1
        end
      end
      nodes << node
    }

    nodes
  end

  def self.script(input, quiet=false)
    lo = Layout.new(input, quiet)
    p lo.instance_eval {@diffeq}
    p lo.layout
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
script(Layout, true)
