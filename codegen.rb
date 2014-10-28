#!/usr/bin/env ruby

require './base'
require './wire'

module Wiring
class Node
  def single
    is_a?(Int)
  end

  def row
    "row_#{index / (single ? 1 : 2)}"
  end

  def column
    type = base_class_name.downcase
    col = single ? nil : (index % 2 == 0) ? 'l' : 'r'
    ["col", type, col].compact.join('_')
  end

  def mapOutput(output)
    output
  end

  def mapInput(input)
    input
  end
end

# All the output nodes are actually one node...
class Output
  def row
    "row_out"
  end

  def column
    "col_out"
  end

  def mapOutput(output)
    error("This doesn't yet make sense.", -1)
  end

  def mapInput(input)
    index
  end
end

class Connection
  def c_code
<<-C_CODE
conn conn_#{@connID} = {
  #{@source.row}, #{@source.column}, out_#{@source.mapOutput(@output)}, #{@destination.row}, #{@destination.column}, in_#{@destination.mapInput(@input)}
};
set_conn (conn_#{@connID});
C_CODE
  end
end
end

class CodeGen
  def self.description
    puts <<-END_DESCRIPTION
## codegen.rb:
##
## This file outputs the C-code that represents the results from wire.rb
##
    END_DESCRIPTION
  end

  def self.usage
    puts "ruby fanout.rb -o=file.c output+"
    puts "\t-o outputs to file.c (can be any file with (c|h)(pp)? extension"
    puts "\tRemaining arguments are up to four orders to output"
    puts "\t-- order 0 is y, order 1 is y', can go up to the LHS of the equation"
    puts "\t-- outputs are uniqued and sorted"
    puts "\tIf input is not piped in, a diffeq will be requested"
  end

  def self.script(input)
    connections = Wire.script(input)
    file = DIFFEQ_ARGS[:file]

    begin
      unless file.nil? then
        error("C file must have valid extension", -1) unless file =~ /\.(c|h)(pp)?$/
        File.open(file, File::WRONLY | File::CREAT | File::TRUNC) {|fout|
          connections.each {|conn|
            fout.puts conn.c_code
            fout.puts
          }
        }
      end
    rescue Exception => e
      error("Error working with the given file #{file}:\n\t#{e.message}", -1)
    end
    self.describe
    puts "<c>"
    connections.each_with_index {|conn, i|
      puts unless i == 0
      puts conn.c_code
    }
    puts "</c>"
  end
end

script(CodeGen) if __FILE__ == $0
