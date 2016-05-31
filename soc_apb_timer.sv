// Copyright 2015 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the “License”); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

`define CFG_REG_LO         5'h0
`define CFG_REG_HI         5'h4
`define TIMER_VAL_LO       5'h8
`define TIMER_VAL_HI       5'hC
`define TIMER_CMP_LO       5'h10
`define TIMER_CMP_HI       5'h14

`define ENABLE_BIT          'd0
`define RESET_BIT           'd1
`define IRQ_BIT             'd2
`define IEM_BIT             'd3
`define CMP_CLR_BIT         'd4
`define ONE_SHOT_BIT        'd5
`define PRESCALER_EN_BIT    'd6
`define PRESCALER_START_BIT 'd8
`define PRESCALER_STOP_BIT  'd15
`define MODE_64_BIT         'd31

module soc_apb_timer
  #(
    parameter ID_WIDTH       = 5
    )
   (
    input  logic                      clk_i,
    input  logic                      rst_ni,
    
    input logic                       req_i,
    input logic [31:0]                addr_i,
    input logic                       wen_i,
    input logic [31:0]                wdata_i,
    input logic [3:0]                 be_i,
    input logic [ID_WIDTH-1:0]        id_i,
    output logic                      gnt_o,
    
    output logic                      r_valid_o,
    output logic                      r_opc_o,
    output logic [ID_WIDTH-1:0]       r_id_o,
    output logic [31:0]               r_rdata_o,
    
    input  logic                      event_lo_i,
    input  logic                      event_hi_i,
    
    output logic                      irq_lo_o,
    output logic                      irq_hi_o
    );
   
   logic 			      s_req,s_wen;
   logic [31:0] 		      s_addr;
   
   logic [31:0] 		      s_cfg_lo, s_cfg_lo_reg;
   logic [31:0] 		      s_cfg_hi, s_cfg_hi_reg;
   logic [31:0] 		      s_timer_val_lo;
   logic [31:0] 		      s_timer_val_hi;
   logic [31:0] 		      s_timer_cmp_lo, s_timer_cmp_lo_reg;
   logic [31:0] 		      s_timer_cmp_hi, s_timer_cmp_hi_reg;
   
   logic 			      s_enable_count_lo,s_enable_count_hi,s_enable_count_prescaler_lo,s_enable_count_prescaler_hi;
   logic 			      s_reset_count_lo,s_reset_count_hi,s_reset_count_prescaler_lo,s_reset_count_prescaler_hi;
   logic 			      s_target_reached_lo,s_target_reached_hi,s_target_reached_prescaler_lo, s_target_reached_prescaler_hi;
   logic 			      s_clear_reset_lo, s_clear_reset_hi;
   
   enum 			      logic [1:0] { TRANS_IDLE, TRANS_RUN } CS, NS;
   
   //**********************************************************
   //*************** FSM FOR GNT AND R_VALID ******************
   //**********************************************************
   
   always_ff @(posedge clk_i, negedge  rst_ni)
     begin
        if(rst_ni == 1'b0)
          CS <= TRANS_IDLE;
        else
          CS <= NS;
     end
   
   always_comb
     begin
	
	gnt_o = 1'b1;
	r_valid_o = 1'b0;
	
	case(CS)
	  
	  TRANS_IDLE:
	    begin
	       if (req_i == 1'b1)
		 NS = TRANS_RUN;
	       else
		 NS = TRANS_IDLE;
	    end
	  
	  TRANS_RUN:
	    begin
	       r_valid_o = 1'b1;
	       if (req_i == 1'b1)
		 NS = TRANS_RUN;
	       else
		 NS = TRANS_IDLE;
	    end
	  
	  default:
	    NS = TRANS_IDLE;
	  
	endcase
	
     end
   
   //**********************************************************
   //*************** DELAYED ADDR, REQ, WEN *******************
   //**********************************************************
   
   always_ff @(posedge clk_i, negedge  rst_ni)
     begin
        if(rst_ni == 1'b0)
	  begin
	     s_req  <= 0;
	     s_wen  <= 0;
             s_addr <= 0;
	     r_id_o <= 0;
	  end
	else
	  begin
	     s_req  <= req_i;
	     s_wen  <= wen_i;
             s_addr <= addr_i;
	     r_id_o <= id_i;
	  end
     end
   
   //**********************************************************
   //*************** PERIPHS INTERFACE ************************
   //**********************************************************
   
   // APB register write logic
   always_comb
     begin
	
	s_cfg_lo       = s_cfg_lo_reg;
	s_cfg_hi       = s_cfg_hi_reg;
	s_timer_cmp_lo = s_timer_cmp_lo_reg;
	s_timer_cmp_hi = s_timer_cmp_hi_reg;
	
	// APB BUS: LOWER PRIORITY
        if (req_i && ~wen_i)
          begin
	     
             case (addr_i[5:0])
	       
	       `CFG_REG_LO:
		 s_cfg_lo       = wdata_i;
	       
	       `CFG_REG_HI:
		 s_cfg_hi       = wdata_i;
	       
	       `TIMER_CMP_LO:
                 s_timer_cmp_lo = wdata_i;
	       
	       `TIMER_CMP_HI:
                 s_timer_cmp_hi = wdata_i;
	       
             endcase
          end
	
	// INPUT EVENTS: HIGHER PRIORITY
	if ( event_lo_i == 1 )
	  s_cfg_lo[`ENABLE_BIT] = 1;
	else
	  begin
	     if ( s_cfg_lo_reg[`MODE_64_BIT] == 1'b0 ) // 32 BIT MODE
	       begin
		  if ( ( s_cfg_lo[`ONE_SHOT_BIT] == 1'b1 ) && ( s_target_reached_lo == 1'b1 ) ) // ONE SHOT FEATURE: DISABLES TIMER ONCE THE TARGET IS REACHED
		    s_cfg_lo[`ENABLE_BIT] = 0;
	       end
	     else
	       begin
		  if ( ( s_cfg_lo[`ONE_SHOT_BIT] == 1'b1 ) && ( s_timer_val_lo  == 32'hFFFFFFFF ) && ( s_target_reached_hi == 1'b1 ) ) // ONE SHOT FEATURE: DISABLES TIMER ONCE LOW COUNTER REACHES 0xFFFFFFFF and HI COUNTER TARGET IS REACHED
		    s_cfg_lo[`ENABLE_BIT] = 0;
	       end
	  end
	
	// INPUT EVENTS: HIGHER PRIORITY
	if ( event_hi_i == 1 )
	  s_cfg_hi[`ENABLE_BIT] = 1;
	else
	  begin
	     if ( ( s_cfg_hi_reg[`MODE_64_BIT] == 1'b0 ) && ( s_cfg_hi[`ONE_SHOT_BIT] == 1'b1 ) && ( s_target_reached_hi == 1'b1 ) ) // ONE SHOT FEATURE: DISABLES TIMER ONCE THE TARGET IS REACHED IN 32 BIT MODE
	       s_cfg_hi[`ENABLE_BIT] = 0;
	  end
	
	// RESET LO
	if (s_reset_count_lo == 1'b1)
	  s_cfg_lo[`RESET_BIT] = 1'b0;
	
	// RESET HI
	if (s_reset_count_hi == 1'b1)
	  s_cfg_hi[`RESET_BIT] = 1'b0;
	
     end
   
   // sequential part
   always_ff @(posedge clk_i, negedge rst_ni)
     begin
        if(~rst_ni)
          begin
	     s_cfg_lo_reg       <= 0;
	     s_cfg_hi_reg       <= 0;
	     s_timer_cmp_lo_reg <= 0;
	     s_timer_cmp_hi_reg <= 0;
          end
        else
          begin
	     s_cfg_lo_reg       <= s_cfg_lo;
	     s_cfg_hi_reg       <= s_cfg_hi;
	     s_timer_cmp_lo_reg <= s_timer_cmp_lo;
	     s_timer_cmp_hi_reg <= s_timer_cmp_hi;
          end
     end
   
   // APB register read logic
   always_comb
     begin
        r_rdata_o = 'b0;
	
        if (s_req && s_wen)
          begin
	     
             case (s_addr[5:0])
               
	       `CFG_REG_LO:
                 r_rdata_o = s_cfg_lo_reg;
	       
               `CFG_REG_HI:
                 r_rdata_o = s_cfg_hi_reg;
	       
               `TIMER_VAL_LO:
                 r_rdata_o = s_timer_val_lo;
	       
	       `TIMER_VAL_HI:
                 r_rdata_o = s_timer_val_hi;
	       
	       `TIMER_CMP_LO:
                 r_rdata_o = s_timer_cmp_lo_reg;
	       
	       `TIMER_CMP_HI:
                 r_rdata_o = s_timer_cmp_hi_reg;
	       
             endcase
	     
          end
	
     end
   
   //**********************************************************
   //*************** CONTROL **********************************
   //**********************************************************
   
   // RESET COUNT SIGNAL GENERATION
   always_comb
     begin
	s_reset_count_lo           = 1'b0;
	s_reset_count_hi           = 1'b0;
	s_reset_count_prescaler_lo = 1'b0;
	s_reset_count_prescaler_hi = 1'b0;
	
	if ( s_cfg_lo_reg[`RESET_BIT] )
	  begin
	     s_reset_count_lo           = 1'b1;
	     s_reset_count_prescaler_lo = 1'b1;
	  end
	else
	  begin
	     if ( s_cfg_lo_reg[`MODE_64_BIT] == 1'b0 ) // 32-bit mode
	       begin
		  if ( ( s_cfg_lo_reg[`CMP_CLR_BIT] == 1'b1 ) && ( s_target_reached_lo == 1'b1 ) ) // if compare and clear feature is enabled the counter is resetted when the target is reached
		    begin
		       s_reset_count_lo  = 1;
		    end
	       end
	     else // 64-bit mode
	       begin
		  if ( ( s_cfg_lo_reg[`CMP_CLR_BIT] == 1'b1 ) && ( s_timer_val_lo  == 32'hFFFFFFFF )  && ( s_target_reached_hi == 1'b1 ) ) // if compare and clear feature is enabled the counter is resetted when the target is reached
		    begin
		       s_reset_count_lo = 1;
		    end
	       end
	  end
	
	if ( s_cfg_hi_reg[`RESET_BIT] )
	  begin
	     s_reset_count_hi           = 1'b1;
	     s_reset_count_prescaler_hi = 1'b1;
	  end
	else
	  begin
	     if ( s_cfg_lo_reg[`MODE_64_BIT] == 1'b0 ) // 32-bit mode
	       begin
		  if ( ( s_cfg_hi_reg[`CMP_CLR_BIT] == 1'b1 ) && ( s_target_reached_hi == 1'b1 ) ) // if compare and clear feature is enabled the counter is resetted when the target is reached
		    begin
		       s_reset_count_hi = 1;
		    end
	       end
	     else // 64-bit mode
	       begin
		  if ( ( s_cfg_lo_reg[`CMP_CLR_BIT] == 1'b1 ) && ( s_timer_val_lo == 32'hFFFFFFFF )  && ( s_target_reached_hi == 1'b1 ) ) // if compare and clear feature is enabled the counter is resetted when the target is reached
		    begin
		       s_reset_count_hi = 1;
		    end
	       end
          end
	
	if ( ( s_cfg_lo_reg[`PRESCALER_EN_BIT] ) && ( s_target_reached_prescaler_lo == 1'b1 ) )
	  begin
	     s_reset_count_prescaler_lo = 1'b1;
	  end

	if ( ( s_cfg_hi_reg[`PRESCALER_EN_BIT] ) && ( s_target_reached_prescaler_hi == 1'b1 ) )
	  begin
	     s_reset_count_prescaler_hi = 1'b1;
	  end
	
     end
   
   // ENABLE SIGNALS GENERATION
   always_comb
     begin
	s_enable_count_lo           = 1'b0;
	s_enable_count_hi           = 1'b0;
	s_enable_count_prescaler_lo = 1'b0;
	s_enable_count_prescaler_hi = 1'b0;
	
	// 32 bit mode lo counter
	if ( s_cfg_lo_reg[`ENABLE_BIT] == 1'b1 )
	  begin
	     if ( s_cfg_lo_reg[`PRESCALER_EN_BIT] == 1'b0 ) // prescaler disabled
	       s_enable_count_lo = 1'b1;
	     else // prescaler enabled
	       begin
		  s_enable_count_lo           = s_target_reached_prescaler_lo;
		  s_enable_count_prescaler_lo = 1'b1;
	       end
	  end
	
	// 32 bit mode hi counter
	if ( s_cfg_hi_reg[`ENABLE_BIT] == 1'b1 ) // counter hi enabled
	  begin
	     if ( s_cfg_hi_reg[`PRESCALER_EN_BIT] == 1'b0 ) // prescaler disabled
	       s_enable_count_hi = 1'b1;
	     else // prescaler enabled
	       begin
		  s_enable_count_hi           = s_target_reached_prescaler_hi;
		  s_enable_count_prescaler_hi = 1'b1;
	       end
	  end
	
	// 64-bit mode
	if ( ( s_cfg_lo_reg[`ENABLE_BIT] == 1'b1 ) && ( s_cfg_lo_reg[`MODE_64_BIT] == 1'b1 ) ) // timer enabled,  64-bit mode
	  begin
	     s_enable_count_hi = ( s_timer_cmp_lo_reg == 32'hFFFFFFFF );
	     if ( ( s_cfg_lo_reg[`PRESCALER_EN_BIT] == 1'b0 ) ) // prescaler disabled
	       begin
		  s_enable_count_lo = 1'b1;
	       end
	     else
	       begin
		  s_enable_count_lo           = s_target_reached_prescaler_lo;
		  s_enable_count_prescaler_lo = 1'b1;
	       end
	  end
     end
   
   // IRQ SIGNALS GENERATION
   assign irq_lo_o = s_target_reached_lo & s_cfg_lo_reg[`IRQ_BIT];
   assign irq_hi_o = s_target_reached_hi & s_cfg_hi_reg[`IRQ_BIT];
   
   //**********************************************************
   //*************** COUNTERS *********************************
   //**********************************************************
   
   soc_apb_timer_counter prescaler_lo_i
     (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      
      .enable_count_i(s_enable_count_prescaler_lo),
      .reset_count_i(s_reset_count_prescaler_lo),
      .compare_value_i({24'd0,s_cfg_lo_reg[`PRESCALER_STOP_BIT:`PRESCALER_START_BIT]}),
      
      .counter_value_o(),
      .target_reached_o(s_target_reached_prescaler_lo)
   );
   
   soc_apb_timer_counter prescaler_hi_i
     (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      
      .enable_count_i(s_enable_count_prescaler_hi),
      .reset_count_i(s_reset_count_prescaler_hi),
      .compare_value_i({24'd0,s_cfg_hi_reg[`PRESCALER_STOP_BIT:`PRESCALER_START_BIT]}),
      
      .counter_value_o(),
      .target_reached_o(s_target_reached_prescaler_hi)
   );
   
   soc_apb_timer_counter counter_lo_i
     (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      
      .enable_count_i(s_enable_count_lo),
      .reset_count_i(s_reset_count_lo),
      .compare_value_i(s_timer_cmp_lo_reg),
      
      .counter_value_o(s_timer_val_lo),
      .target_reached_o(s_target_reached_lo)
   );
   
   soc_apb_timer_counter counter_hi_i
     (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      
      .enable_count_i(s_enable_count_hi),
      .reset_count_i(s_reset_count_hi),
      .compare_value_i(s_timer_cmp_hi_reg),
      
      .counter_value_o(s_timer_val_hi),
      .target_reached_o(s_target_reached_hi)
      );
   
endmodule
