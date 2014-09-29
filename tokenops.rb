
require './base'

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
    return self if self.any? {|sym, coef, (x, xs), (d, *orders)| xs > 0}
    lowest = self.map {|sym, coef, (x, xs), (d, *orders)| orders.min}.compact.min || 0
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