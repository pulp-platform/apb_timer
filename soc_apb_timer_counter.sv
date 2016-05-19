// Copyright 2015 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the “License”); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

module soc_apb_timer_counter
(
   input  logic        clk_i,
   input  logic        rst_ni,

   input  logic        reset_count_i,
   input  logic        enable_count_i,
   input  logic [31:0] compare_value_i,

   output logic [31:0] counter_value_o,
   output logic        target_reached_o
);

   logic [31:0]        s_count, s_count_reg;

   // COUNTER
   always_comb
   begin
      s_count = s_count_reg;

      // start counting
      if ( reset_count_i == 1 )
         s_count = 0;
      else
      begin
         if ( enable_count_i == 1 ) // the counter is increased if counter is enabled and there is a tick
            s_count = s_count_reg + 1;
      end
   end

   always_ff@(posedge clk_i, negedge rst_ni)
   begin
      if (rst_ni == 0)
         s_count_reg <= 0;
      else
         s_count_reg <= s_count;
   end

   // COMPARATOR
   always_ff@(posedge clk_i, negedge rst_ni)
   begin
      if (rst_ni == 0)
         target_reached_o <= 1'b0;
      else
         if ( s_count == compare_value_i )
            target_reached_o <= 1'b1;
         else
            target_reached_o <= 1'b0;
   end
   
   assign counter_value_o = s_count_reg;

endmodule