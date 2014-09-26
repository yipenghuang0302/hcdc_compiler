
require './base'
require './wire'

module Wiring
class Connection
  def c_code
<<-C_CODE
conn conn_#{@connID} = {
  #{@source.row}, #{@source.column}, out_#{@output-1}, #{@destination.row}, #{@destination.column}, in_#{@input}
};
set_conn (conn_#{@connID});
C_CODE
  end
end
end

class CodeGen
  def self.script(input, quiet=false, readout)
    Wire.script(input, quiet, readout).each {|conn|
      puts conn.c_code
      puts
    }
  end
end

script(CodeGen, true, ARGV.shift.to_i) if __FILE__ == $0

=begin

conn conn_2 = {
  row_1, col_mul_l, out_0, row_1, col_int, in_0
};
set_conn (conn_2); 

=end