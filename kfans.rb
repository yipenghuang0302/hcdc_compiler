#!/usr/bin/env ruby

require './base'
require './fanout'
## See description method below for info.

class KFans
  def self.updateMul(tosplit, fanto, mul, key)
    return [fanto, mul[:right]] if mul[:left] == tosplit
    return [mul[:left], fanto] if mul[:right] == tosplit
    error("Cannot find #{tosplit.inspect} in mul #{mul.inspect} (#{key.inspect})", -1)
  end

  def self.updateAdd(tosplit, fanto, add, key)
    where = add[:terms].index(tosplit)
    error("Cannot find #{tosplit.inspect} in #{add.inspect} (#{key.inspect})", -1) if where.nil?
    terms = add[:terms].dup
    terms[where] = fanto
    return terms
  end

  def self.splitFans(kfan, fanout)
    tosplit = fanout[:outputs].select {|key, outputs| outputs.length > kfan}.map {|key, outputs| key[:ref]}
    return fanout if tosplit.empty?
    fanid = fanout[:fan].keys.max + 1
    tosplit = {:type => :fan, :ref => tosplit.min}
    fanto = {:type => :fan, :ref => fanid}

    fanout[:fan][fanid] = tosplit
    outputs = fanout[:outputs][tosplit]
    front, back = outputs.take(kfan-1), outputs.drop(kfan-1)
    fanout[:outputs][tosplit] = [*front, fanto]
    fanout[:outputs][fanto] = *back

    back.reject {|key| [:var, :output].include?(key[:type])}.each {|key|
      if key[:type] == :mul then
        mul = fanout[:mul][key[:ref]]
        mul[:left], mul[:right] = *KFans.updateMul(tosplit, fanto, mul, key)
      elsif key[:type] == :add then
        add = fanout[:add][key[:ref]]
        add[:terms] = KFans.updateAdd(tosplit, fanto, add, key)
      else
        error("Unknown node type #{key.inspect}")
      end
    }

    fanout[:node] = fanto if fanout[:node] == tosplit
    KFans.splitFans(kfan, fanout)
  end

  def self.updateOutput(fanout)
    fanout.update(:output => fanout[:fan].keys.map {|key| [key, fanout[:outputs][{:type => :fan, :ref => key}]]}.select {|key, output|
      output.any? {|out| out[:type] == :output}
    }.map {|key, output| [key, output.select {|out| out[:type] == :output}]}.inject(Hash.new) {|h, (k, o)|
      error("Fan #{key} wired to more than one output", -1) if o.length > 1
      o = o[0][:ref]
      h.update(o => {:type => :fan, :ref => k})
    })
  end

  def self.description
    puts <<-END_DESCRIPTION
## kfans.rb:
##
## This merely takes the output of fanout.rb and adds fans so that each fan
## has at most fanout 3. The fanout description can be seen on its own.
##
    END_DESCRIPTION
  end

  def self.usage
    puts "ruby kfans.rb output+"
    puts "\tArguments are up to four orders to output"
    puts "\t-- order 0 is y, order 1 is y', can go up to the LHS of the equation"
    puts "\t-- outputs are uniqued and sorted"
    puts "\tIf input is not piped in, a diffeq will be requested"
  end

  def self.script(input)
    kfans = KFans.updateOutput(KFans.splitFans(DIFFEQ_ARGS[:kfan], Fanout.script(input)))
    self.describe
    puts "<kfan=#{DIFFEQ_ARGS[:kfan]}>"
    pp kfans
    puts "</kfan>"

    return kfans
  end
end

script(KFans) if __FILE__ == $0
