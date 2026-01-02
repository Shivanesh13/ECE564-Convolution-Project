module dut #(
  parameter int DRAM_ADDRESS_WIDTH = 32,
  parameter int SRAM_ADDRESS_WIDTH = 10,
  parameter int DRAM_DQ_WIDTH = 8,
  parameter int SRAM_DATA_WIDTH = 32
)(
  // System Signals
  input  wire                             clk           ,
  input  wire                             reset_n       , 
 
  // Control signals
  input  wire                             start         ,
  output wire                             ready         ,

  // DRAM Input memory interface
  output wire   [1:0]                     input_CMD     ,  // 2'b00=IDLE, 2'b01=READ, 2'b10=WRITE
  output wire   [DRAM_ADDRESS_WIDTH-1:0]  input_addr    ,
  input  wire   [DRAM_DQ_WIDTH-1:0]       input_dout    ,
  output wire   [DRAM_DQ_WIDTH-1:0]       input_din     ,
  output wire                             input_oe      ,

  // DRAM Output memory interface
  output wire   [1:0]                     output_CMD    ,  // 2'b00=IDLE, 2'b01=READ, 2'b10=WRITE
  output wire   [DRAM_ADDRESS_WIDTH-1:0]  output_addr   ,
  input  wire   [DRAM_DQ_WIDTH-1:0]       output_dout   ,
  output wire   [DRAM_DQ_WIDTH-1:0]       output_din    ,
  output wire                             output_oe     ,

  // Port A: Read Port 
  output wire  [SRAM_ADDRESS_WIDTH-1 :0] read_address  ,
  input  wire  [SRAM_DATA_WIDTH-1 :0]    read_data     ,
  output wire                            read_enable   , 
  
  //---------------------------------------------------------------
  // Port B: Write Port 
  output   wire  [SRAM_ADDRESS_WIDTH-1 :0] write_address ,
  output   wire  [SRAM_DATA_WIDTH-1 :0]    write_data    ,
  output   wire                            write_enable          


);
typedef enum logic [2:0] {IDLE,READY,KERNEL_READ_DATA,KERNEL_STORE_DATA,DATA_STORE,DRAM_READ_WINDUP,SRAM_READ_WINDUP} input_states;
 typedef enum logic [3:0] {WAIT,WINDUP_READ, LAST_READ_WINDUP,SRAM_READ0,SRAM_READ1,SRAM_READ2,SRAM_READ3,SRAM_READ4,SRAM_READ5,SRAM_READ6,SRAM_READ7} control_states;
 typedef enum logic [2:0] {WAIT_M,INITIAL_LOAD,LOAD0,LOAD1} multi_states;
 typedef enum logic [1:0] {WAIT_O,SEND_DATA,WAIT_DELAY} output_states;

 localparam BURST_SIZE = 8;
 localparam COLUMN_ADDR = 10'b00_0000_0111;
 localparam LOG2BURST_SIZE = 3;
 localparam TOTAL_ROW = 1024;
 localparam LOG2_TOTAL_ROW = 10;
 localparam FIRST_POINTER = 0;
 localparam SECOND_POINTER = 256;
 localparam POINTER_INCREMENT = 256;
 localparam THIRD_POINTER = 512;
 localparam FOURTH_POINTER = 768;
 localparam INITIAL_ROW_STORE = 4;
 localparam INITIAL_INPUT_ADDR = 32'h0000_0010;
 localparam FINAL_OUTPUT_ADDR = 17'h07fc0;
 localparam CMD_IDLE = 2'b00;
 localparam CMD_READ = 2'b01;
 localparam CMD_WRITE = 2'b10;
 localparam PIPELINED_DEPTH = 7;

  control_states c_state,c_nxt_state; 
  multi_states m_state, m_nxt_state;//
  input_states i_state, i_nxt_state;//
  logic [1:0] i_CMD_ff, i_CMD_l, o_CMD_l, o_CMD_ff;
  logic ready_ff,ready_l,i_oe_ff,i_oe_l, o_oe_ff;
  logic [DRAM_ADDRESS_WIDTH-1:0] i_addr_l, i_addr_ff, o_addr_ff;

  logic signed [7:0] kernel_ram [0:15];

  logic read_start,kernel_row_counter,valid_kernel_data, valid_kernel_data_d,valid_data,valid_data_d;
  logic [2:0] kernel_delay_counter;
  logic [2:0] kernel_addr_counter,data_addr_counter;
  logic signed [DRAM_DQ_WIDTH-1:0] i_dout, o_dout;
  logic [6:0] data_column_counter;
  logic [9:0] data_calculated_addr,data_row_counter_d,data_row_counter_2d;
  logic [10:0] data_row_counter;
  logic [3:0] kernel_calculated_addr;

  logic signed [7:0] register [0:7];
  logic signed [7:0] temp_register [0:7];

  logic signed [15:0] multi_result1[0:15];
  logic signed [15:0] multi_result2[0:15];
  logic signed [15:0] f_multi_result1[0:15];
  logic signed [15:0] f_multi_result2[0:15];
  logic signed [16:0] partial_sum1_result1[0:7];
  logic signed [16:0] partial_sum1_result2[0:7];
  logic signed [17:0] partial_sum2_result1[0:3];
  logic signed [17:0] partial_sum2_result2[0:3];
  logic signed [18:0] partial_sum3_result1[0:1];
  logic signed [18:0] partial_sum3_result2[0:1];
  logic signed [19:0] convo_result1_temp,convo_result2_temp,convo_result1,convo_result2,final_avrg;
  logic signed [21:0] partial_avrg;
  logic signed [7:0]  clamped_out;

  logic start_fetching_store;
  logic begin_computation,begin_computation_d,begin_rewrite,begin_rewrite_d;
  logic [1:0] s_row_counter;
  logic [7:0] s_colm_counter;

  logic [SRAM_ADDRESS_WIDTH - 1: 0] sram_write_addr, sram_read_addr;
  logic [SRAM_DATA_WIDTH - 1: 0] sram_read_data, sram_write_data,sram_temp_write;
  logic sram_read_enable, sram_write_enable;

  logic signed [SRAM_DATA_WIDTH - 1: 0] temp_sram_buff0_0 [0:3];
  logic signed [SRAM_DATA_WIDTH - 1: 0] temp_sram_buff0_1 [0:3];
  logic signed [2*SRAM_DATA_WIDTH + 24 - 1: 0] main_sram_buff_0    [0:3];
  logic signed [2*SRAM_DATA_WIDTH + 24 - 1: 0] main_sram_buff_1    [0:3];

  logic shift_left,valid_computation;

  logic signed [7:0] source_data_1 [0:15];
  logic signed [7:0] source_data_2 [0:15];

  logic valid_avrg_2d;

  logic [2:0] computation_counter;
  logic [6:0] number_dw;
  logic valid_computation_d, valid_computation_2d, valid_computation_3d, valid_computation_4d, valid_computation_5d,valid_computation_6d,valid_computation_7d;
  logic extend_read_valid, extend_read_valid_d,extend_read_valid_2d, extend_read_valid_3d, extend_read_valid_4d,extend_read_valid_5d,extend_read_valid_6d,extend_read_valid_7d;
  logic [PIPELINED_DEPTH-1:0] valid_computation_pipelined;
  logic [PIPELINED_DEPTH-1:0] extend_read_pipelined;
  
  logic signal_toggler;
  logic valid_avrg, valid_avrg_d;
  logic [9:0] extend_read_counter;


output_states o_state,o_nxt_state;

// synopsys sync_set_reset "reset_n"
  always_ff @(posedge clk) begin
    if(!reset_n) begin
      i_state <= IDLE;
      c_state <= WAIT;
      m_state <= WAIT_M;
      o_state <= WAIT_O;
    end
    else begin
      o_state <= o_nxt_state;
      m_state <= m_nxt_state;
      i_state <= i_nxt_state;
      c_state <= c_nxt_state;
    end 
  end

  // SRAM Inputs : 
  assign write_address = sram_write_addr;
  assign read_address = sram_read_addr;
  assign write_data = sram_write_data;
  assign sram_read_data = read_data;
  assign read_enable = sram_read_enable;
  assign write_enable = sram_write_enable;

  // DRAM Output: 
  assign output_din = o_dout;
  assign output_oe = o_oe_ff;
  assign output_addr = o_addr_ff;
  assign output_CMD = o_CMD_ff;


  // Input States Values: 
  assign ready = ready_ff;
  assign input_CMD = i_CMD_ff;
  assign input_addr = i_addr_ff;
  assign input_oe = i_oe_ff;

  assign kernel_calculated_addr = (kernel_row_counter << LOG2BURST_SIZE) | (COLUMN_ADDR);
  assign data_calculated_addr = (data_column_counter << LOG2BURST_SIZE) | (COLUMN_ADDR);

  logic valid_data_stored;
  logic [5:0] computed_row_counter;
  logic [2:0] valid_data_counter,valid_data_counter_d;
  logic signed [7:0] pre_stage_buffer [0:7];
  logic signed [7:0] final_stage_buffer [0:7];
  logic signed [16:0] final_output_address;
  logic start_delay_counter,start_sending_data, valid_output_data;
  logic [2:0] write_delay_counter;



// synopsys sync_set_reset "reset_n"
  always_ff @(posedge clk ) begin
    if(!reset_n) begin
      valid_data_counter <= 'b0;
      valid_data_stored <= 'b0;
      computed_row_counter <= 'b0;
      valid_data_counter_d <= 'b0;
      final_output_address <= 'b0;
      o_CMD_ff <= 'b0;
      o_oe_ff  <= 'b0;
      o_addr_ff <= 'b0;
      o_dout <= 'b0;
    end else begin
      valid_data_counter_d <= valid_data_counter;
      
      if(valid_data_counter_d == BURST_SIZE-1 && valid_data_counter == 0) begin
        computed_row_counter <= computed_row_counter + 1;
      end 

      if(valid_data_counter_d == BURST_SIZE-1 && !valid_avrg_2d && computed_row_counter != 63)begin
        final_stage_buffer[0] <= pre_stage_buffer[7];
        final_stage_buffer[1] <= pre_stage_buffer[6];
        final_stage_buffer[2] <= pre_stage_buffer[5];
        final_stage_buffer[3] <= pre_stage_buffer[4];
        final_stage_buffer[4] <= pre_stage_buffer[3];
        final_stage_buffer[5] <= pre_stage_buffer[2];
        final_stage_buffer[6] <= pre_stage_buffer[1];
        final_stage_buffer[7] <= pre_stage_buffer[0];
      end else if(valid_data_counter == BURST_SIZE-1 && !valid_avrg_2d && computed_row_counter == 63) begin
        final_stage_buffer[0] <= 'b0;
        final_stage_buffer[1] <= pre_stage_buffer[6];
        final_stage_buffer[2] <= pre_stage_buffer[5];
        final_stage_buffer[3] <= pre_stage_buffer[4];
        final_stage_buffer[4] <= pre_stage_buffer[3];
        final_stage_buffer[5] <= pre_stage_buffer[2];
        final_stage_buffer[6] <= pre_stage_buffer[1];
        final_stage_buffer[7] <= pre_stage_buffer[0];
      end

      if(valid_avrg_2d) begin
        pre_stage_buffer[valid_data_counter] <= clamped_out;
        valid_data_counter <= valid_data_counter + 1;
        o_CMD_ff <= 'b0;
      end else if(valid_data_counter == BURST_SIZE-1 && !valid_avrg_2d && computed_row_counter != 63) begin
        o_CMD_ff <= 2'b10;
        o_addr_ff <= final_output_address << LOG2BURST_SIZE;
        final_output_address <= final_output_address + 1;
      end else if(valid_data_counter_d == BURST_SIZE-1 && !valid_avrg_2d && computed_row_counter == 63)begin
        o_CMD_ff <= 'b0;
        valid_data_counter <= 'b0;
      end else if(valid_data_counter == BURST_SIZE-1 && !valid_avrg_2d && computed_row_counter == 63) begin
        o_CMD_ff <= 2'b10;
        o_addr_ff <= final_output_address << LOG2BURST_SIZE;
        final_output_address <= final_output_address + 1;
      end
      else begin
        o_CMD_ff <= 'b0;
      end

      if(start_delay_counter || start_sending_data) begin
        write_delay_counter <= 'b0;
      end else begin
        write_delay_counter <= write_delay_counter + 1;
      end

      if(valid_output_data) begin
        o_dout <= final_stage_buffer[0];
        final_stage_buffer[0] <= final_stage_buffer[1];
        final_stage_buffer[1] <= final_stage_buffer[2];
        final_stage_buffer[2] <= final_stage_buffer[3];
        final_stage_buffer[3] <= final_stage_buffer[4];
        final_stage_buffer[4] <= final_stage_buffer[5];
        final_stage_buffer[5] <= final_stage_buffer[6];
        final_stage_buffer[6] <= final_stage_buffer[7];
        final_stage_buffer[7] <= 'b0;
        o_oe_ff <= 1'b1;
      end else begin
        o_oe_ff <= 1'b0;
      end
    end
  end


  always_comb begin
    start_delay_counter = 1'b0;
    start_sending_data = 1'b0;
    valid_output_data = 1'b0;
    o_nxt_state = WAIT_O;
    casex (o_state)
      WAIT_O: begin
        if(valid_data_counter == BURST_SIZE-1 && valid_avrg_2d) begin
          start_delay_counter = 1'b1;
          o_nxt_state = WAIT_DELAY;
        end 
        if(computed_row_counter == 63 && valid_data_counter_d == BURST_SIZE-1) begin
          start_delay_counter = 1'b1;
          o_nxt_state = WAIT_DELAY;
        end
      end 
      WAIT_DELAY: begin
        o_nxt_state = WAIT_DELAY;
        if(write_delay_counter == LOG2BURST_SIZE) begin
          start_sending_data = 1'b1;
          o_nxt_state = SEND_DATA;
          valid_output_data = 1'b1;
        end
      end
      SEND_DATA: begin
        o_nxt_state = SEND_DATA;
        valid_output_data = 1'b1;
        if(write_delay_counter == BURST_SIZE-1) begin
          o_nxt_state = WAIT_O;
          valid_output_data = 1'b0;
        end 
      end
      default: begin
        valid_output_data = 1'b0;
        o_nxt_state = WAIT_O;
      end
    endcase
  end



// synopsys sync_set_reset "reset_n"
  always_ff @(posedge clk) begin
    if(!reset_n) begin
      ready_ff  <= 1'b0;
      i_CMD_ff  <= 2'b0;
      i_addr_ff <= 'b0;
      kernel_addr_counter <= 'b0;
      kernel_delay_counter <= 'b0;
      valid_kernel_data_d <= 'b0;
      kernel_row_counter <= 'b0;
      i_oe_ff <= 'b0;
    end
    else begin
      valid_kernel_data_d <= valid_kernel_data;
      i_addr_ff <= i_addr_l;
      ready_ff  <= ready_l;
      i_CMD_ff  <= i_CMD_l;
      i_oe_ff   <= i_oe_l;
      if(read_start) begin
        kernel_delay_counter <= kernel_delay_counter + 1;
      end
      else begin
        kernel_delay_counter <= 'b0;
      end

      if(valid_kernel_data_d) begin
        kernel_addr_counter <= kernel_addr_counter + 1;
        if(kernel_addr_counter == BURST_SIZE-1) begin
          kernel_row_counter <= kernel_row_counter + 1;
        end
        kernel_ram[kernel_calculated_addr-kernel_addr_counter] <= i_dout;
      end else begin
        kernel_addr_counter <= 'b0;
      end

      if(valid_kernel_data | valid_data)
        i_dout <= input_dout;
      else 
        i_dout <= 'b0;
    end
  end

// synopsys sync_set_reset "reset_n"
  always_ff @(posedge clk) begin
    if(!reset_n) begin
      valid_data_d <= 'b0;
      data_row_counter <= 'b0;
      data_row_counter_d <= 'b0;
      data_row_counter_2d <= 'b0;
      data_column_counter <= 'b0;
      data_addr_counter <= 'b0;
      begin_rewrite_d <= 'b0;
      s_row_counter <= 'b0;
      s_colm_counter <= 'b0;
      begin_rewrite <= 'b0;
      valid_avrg_2d <= 'b0;
    end else begin
      valid_data_d <= valid_data;
      valid_avrg_2d <= valid_avrg_d;
      begin_rewrite_d <= begin_rewrite;
      data_row_counter_d <= data_row_counter[9:0];
      data_row_counter_2d <= data_row_counter_d;

      
      if(valid_data_d) begin
        data_addr_counter <= data_addr_counter + 1;
        if(data_addr_counter == BURST_SIZE-1) begin
          data_column_counter <= data_column_counter + 1;
          if(data_column_counter == 127) 
            data_row_counter <= data_row_counter + 1;
        end

        if(data_row_counter <= LOG2BURST_SIZE) begin
          begin_rewrite <= 1'b0;
          if(data_addr_counter == LOG2BURST_SIZE || data_addr_counter == BURST_SIZE-1) begin
            sram_write_addr <= (data_row_counter << BURST_SIZE) + ((data_calculated_addr-data_addr_counter) >> (LOG2BURST_SIZE-1));
            sram_write_data <= {i_dout,sram_temp_write[31:8]};
            sram_temp_write <= {i_dout,sram_temp_write[31:8]};
            sram_write_enable <= 1'b1;
          end else begin
            sram_temp_write <= {i_dout,sram_temp_write[31:8]};
            sram_write_enable <= 1'b0;
          end         
        end 
        else begin
          temp_register[7 - data_addr_counter] <= i_dout;
          if(data_addr_counter == 7) begin
            register[7] <= temp_register[7];
            register[6] <= temp_register[6];
            register[5] <= temp_register[5];
            register[4] <= temp_register[4];
            register[3] <= temp_register[3];
            register[2] <= temp_register[2];
            register[1] <= temp_register[1];
            register[0] <= i_dout;
            begin_rewrite <= 1'b1;
          end else begin
            begin_rewrite <= 1'b0;
          end

          if(begin_rewrite) begin
            sram_write_enable <= 1'b1;
            sram_write_addr <= ((s_row_counter << 8) + s_colm_counter);
            sram_write_data <= {register[0],register[1],register[2],register[3]};
            s_colm_counter <= s_colm_counter + 1;
          end else if(begin_rewrite_d) begin
            sram_write_enable <= 1'b1;
            s_colm_counter <= s_colm_counter + 1;
            sram_write_addr <= ((s_row_counter << 8) + s_colm_counter);
            sram_write_data <= {register[4],register[5],register[6],register[7]};
            if(s_colm_counter == 255) begin
              s_row_counter <= (s_row_counter + 1);
            end
          end
          else begin
            sram_write_enable <= 'b0;
          end
        end
      end
      else begin
        sram_write_enable <= 1'b0;
        data_addr_counter <= 'b0;
      end
    end
  end

  logic valid_sram_read,valid_sram_read_d,valid_sram_read_2d;
  control_states c_state_d,c_state_2d;
  logic [9:0] partial_read_address;



// synopsys sync_set_reset "reset_n"
  always_ff @(posedge clk ) begin 
    if(!reset_n) begin
      partial_read_address <= 'b0;
      sram_read_addr <= 'b0;
      sram_read_enable <= 'b0;
      begin_computation <= 'b0;
      for(int i = 0;i < 4;i = i + 1) begin
        temp_sram_buff0_0[i] <= 'b0;
        temp_sram_buff0_1[i] <= 'b0;
      end
    end else begin
      c_state_d <= c_state;
      c_state_2d <= c_state_d;
      valid_sram_read_d <= valid_sram_read;
      valid_sram_read_2d <= valid_sram_read_d;
      if(data_row_counter >= 4) begin
        if(valid_sram_read) begin
          casex (c_state)
            SRAM_READ0: begin
              sram_read_addr <= FIRST_POINTER + (partial_read_address);
              sram_read_enable <= 1'b1;
            end
            SRAM_READ1: begin
              sram_read_addr <= SECOND_POINTER + (partial_read_address);;
              sram_read_enable <= 1'b1;
            end
            SRAM_READ2: begin
              sram_read_addr <= THIRD_POINTER + (partial_read_address);
              sram_read_enable <= 1'b1;
            end
            SRAM_READ3: begin
              sram_read_addr <= FOURTH_POINTER + (partial_read_address );
              sram_read_enable <= 1'b1;
              partial_read_address <= partial_read_address + 1;
            end
            SRAM_READ4: begin
              sram_read_addr <= FIRST_POINTER + (partial_read_address);
              sram_read_enable <= 1'b1;
            end
            SRAM_READ5: begin
              sram_read_addr <= SECOND_POINTER + (partial_read_address );
              sram_read_enable <= 1'b1;
            end
            SRAM_READ6: begin
              sram_read_addr <= THIRD_POINTER + (partial_read_address);
              sram_read_enable <= 1'b1;
            end
            SRAM_READ7: begin
              sram_read_addr <= FOURTH_POINTER + (partial_read_address);
              sram_read_enable <= 1'b1;
              partial_read_address <= partial_read_address + 1;
            end
            WAIT,WINDUP_READ: begin
              sram_read_enable <= 1'b0;
            end
            default: begin
              sram_read_addr <= 'b0;
              sram_read_enable <= 1'b0;
            end
          endcase
        end
        else begin
          sram_read_enable <= 1'b0;
          if(!valid_sram_read && valid_sram_read_d) begin
            partial_read_address <= partial_read_address + POINTER_INCREMENT;
          end
        end
        if(valid_sram_read_2d) begin
          casex (c_state_2d)
            SRAM_READ0: begin
              temp_sram_buff0_0[0] <= sram_read_data;
              begin_computation <= 1'b0;
            end
            SRAM_READ1: begin
              //temp_sram_buff0_1[0] <= sram_read_data;
              temp_sram_buff0_0[1] <= sram_read_data;
            end
            SRAM_READ2: begin
              //temp_sram_buff0_0[1] <= sram_read_data;
              temp_sram_buff0_0[2] <= sram_read_data;
            end
            SRAM_READ3: begin
              //temp_sram_buff0_1[1] <= sram_read_data;
              temp_sram_buff0_0[3] <= sram_read_data;
            end
            SRAM_READ4: begin
              temp_sram_buff0_1[0] <= sram_read_data;
            end
            SRAM_READ5: begin
              temp_sram_buff0_1[1] <= sram_read_data;
            end
            SRAM_READ6: begin
              temp_sram_buff0_1[2] <= sram_read_data;
              begin_computation <= 1'b0;
            end
            SRAM_READ7: begin
              temp_sram_buff0_1[3] <= sram_read_data;
              begin_computation <= 1'b1;
            end 
            default: begin
              begin_computation <= 1'b0;
            end
          endcase
        end
        else begin
          begin_computation <= 1'b0;
        end
      end
    end 
  end


  always_comb begin
    valid_sram_read = 1'b0;
    c_nxt_state = WAIT;
    casex (c_state)
      WAIT: if(start_fetching_store) begin
              c_nxt_state = SRAM_READ0;
              valid_sram_read = 1'b0;
            end else begin
              c_nxt_state = WAIT;
            end
      SRAM_READ0: begin
        c_nxt_state = SRAM_READ1; 
        valid_sram_read = 1'b1;
      end
      SRAM_READ1: begin
        c_nxt_state = SRAM_READ2; 
        valid_sram_read = 1'b1;
      end
      SRAM_READ2: begin
        c_nxt_state = SRAM_READ3; 
        valid_sram_read = 1'b1;
      end
      SRAM_READ3: begin
        c_nxt_state = SRAM_READ4; 
        valid_sram_read = 1'b1;
      end
      SRAM_READ4: begin
        c_nxt_state = SRAM_READ5; 
        valid_sram_read = 1'b1;
      end
      SRAM_READ5: begin
        c_nxt_state = SRAM_READ6; 
        valid_sram_read = 1'b1;
      end
      SRAM_READ6: begin
        c_nxt_state = SRAM_READ7;
        valid_sram_read = 1'b1;
      end
      SRAM_READ7: begin
        c_nxt_state = SRAM_READ0; 
        valid_sram_read = 1'b1;
        if(start_fetching_store) begin
          c_nxt_state = SRAM_READ0; 
          valid_sram_read = 1'b1;
        end else if(data_row_counter[0] && data_row_counter != TOTAL_ROW-1) begin
          valid_sram_read = 1'b1;
          c_nxt_state = WINDUP_READ;
        end else if(data_row_counter == TOTAL_ROW) begin
          valid_sram_read = 1'b1;
          c_nxt_state = LAST_READ_WINDUP;
        end
      end
      LAST_READ_WINDUP: begin
        valid_sram_read = 1'b1;
        c_nxt_state = WAIT;
      end
      WINDUP_READ: begin
        valid_sram_read = 1'b0;
          c_nxt_state = WAIT;
      end
    endcase
  end

      assign valid_computation_d  = valid_computation_pipelined[0];
      assign valid_computation_2d = valid_computation_pipelined[1];
      assign valid_computation_3d = valid_computation_pipelined[2];
      assign valid_computation_4d = valid_computation_pipelined[3];
      assign valid_computation_5d = valid_computation_pipelined[4];
      assign valid_computation_6d = valid_computation_pipelined[5];
      assign valid_computation_7d = valid_computation_pipelined[6];

      assign extend_read_valid_d  = extend_read_pipelined[0];
      assign extend_read_valid_2d = extend_read_pipelined[1];
      assign extend_read_valid_3d = extend_read_pipelined[2];
      assign extend_read_valid_4d = extend_read_pipelined[3];
      assign extend_read_valid_5d = extend_read_pipelined[4];
      assign extend_read_valid_6d = extend_read_pipelined[5];
      assign extend_read_valid_7d = extend_read_pipelined[6];



// synopsys sync_set_reset "reset_n"
  always_ff @(posedge clk ) begin 
    if(!reset_n) begin
      convo_result1_temp <= 'b0;
      convo_result2_temp <= 'b0; 
      convo_result1 <= 'b0;
      convo_result2 <= 'b0;
      // for(int i=0;i<16;i=i+1) begin
      //   f_multi_result1[i] <= 'b0;
      //   f_multi_result2[i] <= 'b0;
      //   partial_sum1_result1[i/2] <= 'b0;
      //   partial_sum1_result2[i/2] <= 'b0;
      //   partial_sum2_result1[i/4] <= 'b0;
      //   partial_sum2_result2[i/4] <= 'b0;
      //   partial_sum3_result1[i/8] <= 'b0;
      //   partial_sum3_result2[i/8] <= 'b0;
      // end
    end else begin
      
      valid_computation_pipelined <= {valid_computation_pipelined[PIPELINED_DEPTH-2:0],valid_computation};
      extend_read_pipelined <= {extend_read_pipelined[PIPELINED_DEPTH-2:0],extend_read_valid};
    
      for(int i = 0; i < 16; i = i + 1) begin
        f_multi_result1[i] <= multi_result1[i];
        f_multi_result2[i] <= multi_result2[i];
      end

      for(int i=0; i < 16; i = i + 2) begin
        partial_sum1_result1[i/2] <= f_multi_result1[i] + f_multi_result1[i+1];
        partial_sum1_result2[i/2] <= f_multi_result2[i] + f_multi_result2[i+1];
      end

      for(int i = 0; i < 8; i = i+2) begin
        partial_sum2_result1[i/2] <= partial_sum1_result1[i] + partial_sum1_result1[i+1];
        partial_sum2_result2[i/2] <= partial_sum1_result2[i] + partial_sum1_result2[i+1];  
      end

      for(int i=0;i < 4; i = i + 2) begin
        partial_sum3_result1[i/2] <= partial_sum2_result1[i] + partial_sum2_result1[i+1];  
        partial_sum3_result2[i/2] <= partial_sum2_result2[i] + partial_sum2_result2[i+1];  
      end

      convo_result1_temp <= partial_sum3_result1[0] + partial_sum3_result1[1];
      convo_result2_temp <= partial_sum3_result2[0] + partial_sum3_result2[1]; // valid_5d

      if(convo_result1_temp > 0) begin
        convo_result1 <= convo_result1_temp;
      end else if(convo_result1_temp <= 0 && convo_result1_temp > -4)
        convo_result1 <= 'b0;
      else 
        convo_result1 <= ((convo_result1_temp+3) >>> 2);

      if(convo_result2_temp > 0) begin
        convo_result2 <= convo_result2_temp;
      end else if(convo_result2_temp <= 0 && convo_result2_temp > -4)
        convo_result2 <= 'b0;
      else 
        convo_result2 <= ((convo_result2_temp+3) >>> 2);
    end 
  end


  assign valid_avrg = ((~signal_toggler) & valid_computation_7d) | extend_read_valid_7d;

// synopsys sync_set_reset "reset_n"
  always_ff @(posedge clk) begin
    if(!reset_n) begin
      signal_toggler <= 'b0;
      valid_avrg_d <= 'b0;
      extend_read_counter <= 'b0;
    end else begin
      if(extend_read_valid_7d) 
        extend_read_counter <= extend_read_counter + 1;
      valid_avrg_d <= valid_avrg;
      if(valid_computation_6d) begin
        signal_toggler <= !signal_toggler;
      end

      if(extend_read_counter == 510) begin
        if(valid_computation_6d || extend_read_valid_6d) begin
          if(!signal_toggler) begin
            partial_avrg <=  convo_result2;
          end else begin
            partial_avrg <=  partial_avrg + convo_result2;
          end
        end
      end else if(valid_computation_6d || extend_read_valid_6d) begin
        if(!signal_toggler) begin
          partial_avrg <= convo_result1 + convo_result2;
        end else begin
          partial_avrg <= partial_avrg + convo_result1 + convo_result2;
        end
      end 

      if(valid_avrg) begin
        if(partial_avrg >= 4) begin
          final_avrg <= partial_avrg >>> 2;
        end else if(partial_avrg <= -4) begin
          final_avrg <= (partial_avrg + 3) >>> 2;
        end else begin
          final_avrg <= 'b0;
        end
      end

      if(valid_avrg_d) begin
        if(final_avrg > 127) begin
          clamped_out <= 8'h7f;
        end else if(final_avrg < -128) begin
          clamped_out <= 8'h80;
        end else begin
          clamped_out <= final_avrg;
        end
      end
    end
  end

  logic shift_left_d;
  logic extend_computation;

// synopsys sync_set_reset "reset_n"
  always_ff @(posedge clk ) begin
    if(!reset_n) begin
      computation_counter <= 'b0;
      number_dw <= 'b0;
      //computed_row_counter <= 'b0;
      shift_left_d <= 'b0;
      extend_computation <= 1'b0;
      // for(int i=0;i<4;i++) begin
      //   main_sram_buff_1[i] <= 'b0;
      //   main_sram_buff_0[i] <= 'b0;
      // end
    end
    else begin
      shift_left_d <= shift_left;
      begin_computation_d <= begin_computation;
      if(begin_computation | extend_computation) begin
        computation_counter <= 'b0;
        number_dw <= number_dw + 1;
      end 
      else begin
        computation_counter <= computation_counter + 1;
      end

      if((number_dw == 8'h7f || number_dw == 8'h00) && computation_counter == 6 && extend_read_counter == 510) begin
        extend_computation <= 1'b1;
      end else begin
        extend_computation <= 1'b0;
      end
    
    
      if((begin_computation | extend_computation) && m_state == WAIT_M) begin
        if(extend_read_counter == 510) begin
          main_sram_buff_1[0] <= main_sram_buff_0[0];
          main_sram_buff_1[1] <= main_sram_buff_0[1];
          main_sram_buff_1[2] <= main_sram_buff_0[2];
          main_sram_buff_1[3] <= main_sram_buff_0[3];

          main_sram_buff_0[0] <= {temp_sram_buff0_0[1],temp_sram_buff0_1[1],24'b0};
          main_sram_buff_0[1] <= {temp_sram_buff0_0[2],temp_sram_buff0_1[2],24'b0};
          main_sram_buff_0[2] <= {temp_sram_buff0_0[3],temp_sram_buff0_1[3],24'b0};
          main_sram_buff_0[3] <= {register[0], register[1], register[2], register[3], register[4], register[5], register[6], register[7], 24'b0};
        end
        else begin
          main_sram_buff_0[0] <= {temp_sram_buff0_0[0],temp_sram_buff0_1[0],24'b0};
          main_sram_buff_0[1] <= {temp_sram_buff0_0[1],temp_sram_buff0_1[1],24'b0};
          main_sram_buff_0[2] <= {temp_sram_buff0_0[2],temp_sram_buff0_1[2],24'b0};
          main_sram_buff_0[3] <= {temp_sram_buff0_0[3],temp_sram_buff0_1[3],24'b0};

          main_sram_buff_1[0] <= {temp_sram_buff0_0[1],temp_sram_buff0_1[1],24'b0};
          main_sram_buff_1[1] <= {temp_sram_buff0_0[2],temp_sram_buff0_1[2],24'b0};
          main_sram_buff_1[2] <= {temp_sram_buff0_0[3],temp_sram_buff0_1[3],24'b0};
          main_sram_buff_1[3] <= {register[0], register[1], register[2], register[3], register[4], register[5], register[6], register[7], 24'b0};
        end 
      end else if((begin_computation | extend_computation) && (m_state == LOAD0 || m_state == INITIAL_LOAD)) begin
        if(extend_read_counter == 510) begin
          main_sram_buff_1[0] <= {main_sram_buff_1[0][79:56],main_sram_buff_0[0][87:24]};
          main_sram_buff_1[1] <= {main_sram_buff_1[1][79:56],main_sram_buff_0[1][87:24]};
          main_sram_buff_1[2] <= {main_sram_buff_1[2][79:56],main_sram_buff_0[2][87:24]};
          main_sram_buff_1[3] <= {main_sram_buff_1[3][79:56],main_sram_buff_0[3][87:24]};

          main_sram_buff_0[0] <= {temp_sram_buff0_0[1],temp_sram_buff0_1[1],24'b0};
          main_sram_buff_0[1] <= {temp_sram_buff0_0[2],temp_sram_buff0_1[2],24'b0};
          main_sram_buff_0[2] <= {temp_sram_buff0_0[3],temp_sram_buff0_1[3],24'b0};
          main_sram_buff_0[3] <= {register[0], register[1], register[2], register[3], register[4], register[5], register[6], register[7], 24'b0};
        end
        else begin
          main_sram_buff_0[0] <= {main_sram_buff_0[0][79:56],temp_sram_buff0_0[0],temp_sram_buff0_1[0]};
          main_sram_buff_0[1] <= {main_sram_buff_0[1][79:56],temp_sram_buff0_0[1],temp_sram_buff0_1[1]};
          main_sram_buff_0[2] <= {main_sram_buff_0[2][79:56],temp_sram_buff0_0[2],temp_sram_buff0_1[2]};
          main_sram_buff_0[3] <= {main_sram_buff_0[3][79:56],temp_sram_buff0_0[3],temp_sram_buff0_1[3]};

          main_sram_buff_1[0] <= {main_sram_buff_1[0][79:56],temp_sram_buff0_0[1],temp_sram_buff0_1[1]};
          main_sram_buff_1[1] <= {main_sram_buff_1[1][79:56],temp_sram_buff0_0[2],temp_sram_buff0_1[2]};
          main_sram_buff_1[2] <= {main_sram_buff_1[2][79:56],temp_sram_buff0_0[3],temp_sram_buff0_1[3]};
          main_sram_buff_1[3] <= {main_sram_buff_1[3][79:56],{register[0], register[1], register[2], register[3], register[4], register[5], register[6], register[7]}};
        end 
      end else if(shift_left) begin
        if(extend_read_counter != 510) begin
          main_sram_buff_0[0] <= main_sram_buff_0[0] << BURST_SIZE;
          main_sram_buff_0[1] <= main_sram_buff_0[1] << BURST_SIZE;
          main_sram_buff_0[2] <= main_sram_buff_0[2] << BURST_SIZE;
          main_sram_buff_0[3] <= main_sram_buff_0[3] << BURST_SIZE;
        end
        main_sram_buff_1[0] <= main_sram_buff_1[0] << BURST_SIZE;
        main_sram_buff_1[1] <= main_sram_buff_1[1] << BURST_SIZE;
        main_sram_buff_1[2] <= main_sram_buff_1[2] << BURST_SIZE;
        main_sram_buff_1[3] <= main_sram_buff_1[3] << BURST_SIZE;
      end else if(begin_computation_d && !valid_computation_d && shift_left_d) begin
        main_sram_buff_0[0] <= {main_sram_buff_1[0][63:0], 24'b0};
        main_sram_buff_0[1] <= {main_sram_buff_1[1][63:0], 24'b0};
        main_sram_buff_0[2] <= {main_sram_buff_1[2][63:0], 24'b0};
        main_sram_buff_0[3] <= {main_sram_buff_1[3][63:0], 24'b0};
      end
    end
  end

  assign source_data_1[0]  = main_sram_buff_0[0][87:80];
  assign source_data_1[1]  = main_sram_buff_0[0][79:72];
  assign source_data_1[2]  = main_sram_buff_0[0][71:64];
  assign source_data_1[3]  = main_sram_buff_0[0][63:56];
  assign source_data_1[4]  = main_sram_buff_0[1][87:80];
  assign source_data_1[5]  = main_sram_buff_0[1][79:72];
  assign source_data_1[6]  = main_sram_buff_0[1][71:64];
  assign source_data_1[7]  = main_sram_buff_0[1][63:56];
  assign source_data_1[8]  = main_sram_buff_0[2][87:80];
  assign source_data_1[9]  = main_sram_buff_0[2][79:72];
  assign source_data_1[10] = main_sram_buff_0[2][71:64];
  assign source_data_1[11] = main_sram_buff_0[2][63:56];
  assign source_data_1[12] = main_sram_buff_0[3][87:80];
  assign source_data_1[13] = main_sram_buff_0[3][79:72];
  assign source_data_1[14] = main_sram_buff_0[3][71:64];
  assign source_data_1[15] = main_sram_buff_0[3][63:56];

  assign source_data_2[0]  = main_sram_buff_1[0][87:80];
  assign source_data_2[1]  = main_sram_buff_1[0][79:72];
  assign source_data_2[2]  = main_sram_buff_1[0][71:64];
  assign source_data_2[3]  = main_sram_buff_1[0][63:56];
  assign source_data_2[4]  = main_sram_buff_1[1][87:80];
  assign source_data_2[5]  = main_sram_buff_1[1][79:72];
  assign source_data_2[6]  = main_sram_buff_1[1][71:64];
  assign source_data_2[7]  = main_sram_buff_1[1][63:56];
  assign source_data_2[8]  = main_sram_buff_1[2][87:80];
  assign source_data_2[9]  = main_sram_buff_1[2][79:72];
  assign source_data_2[10] = main_sram_buff_1[2][71:64];
  assign source_data_2[11] = main_sram_buff_1[2][63:56];
  assign source_data_2[12] = main_sram_buff_1[3][87:80];
  assign source_data_2[13] = main_sram_buff_1[3][79:72];
  assign source_data_2[14] = main_sram_buff_1[3][71:64];
  assign source_data_2[15] = main_sram_buff_1[3][63:56];


  always_comb begin
    valid_computation = 1'b0;
    shift_left = 1'b0;
    extend_read_valid = 1'b0;
    m_nxt_state = WAIT_M;
    for(int i = 0; i < 16; i = i + 1) begin
      multi_result1[i] = 'b0;
      multi_result2[i] = 'b0;
    end
    casex (m_state)
      WAIT_M: begin
        m_nxt_state = WAIT_M;
        shift_left = 1'b0;
        if(begin_computation) begin
          m_nxt_state = INITIAL_LOAD;
        end
      end
      INITIAL_LOAD: begin
          m_nxt_state = INITIAL_LOAD;
          if(begin_computation) begin
            m_nxt_state = LOAD0;
          end 
          casex (computation_counter)
            0,1,2,3,4: begin
            shift_left = 1'b1;
            if(computation_counter == 4)
              shift_left = 1'b0;
            valid_computation = 1'b1;
            for(int i = 0; i < 16; i = i + 1) begin
              multi_result1[i] = kernel_ram[i] * source_data_1[i];
              multi_result2[i] = kernel_ram[i] * source_data_2[i];
            end
          end 
            default: begin
            shift_left = 1'b0;
            valid_computation = 1'b0;
          end
          endcase
        end
      LOAD0: begin
        m_nxt_state = LOAD0;
        shift_left = 1'b1;
        valid_computation = 1'b1;
        if(number_dw == 0 && computation_counter == 7 && extend_read_counter != 510) begin
          valid_computation = 1'b0;
          extend_read_valid = 1'b1;
          m_nxt_state = WAIT_M;
        end else if(extend_read_counter == 510 && number_dw == 1 && computation_counter == 7) begin
          valid_computation = 1'b0;
          extend_read_valid = 1'b1;
          m_nxt_state = WAIT_M;
        end
        for(int i = 0; i < 16; i = i + 1) begin
          multi_result1[i] = kernel_ram[i] * source_data_1[i];
          multi_result2[i] = kernel_ram[i] * source_data_2[i];
        end
        
      end 
    endcase
  end 


  always_comb begin
    ready_l = 1'b0;
    i_CMD_l = 2'b00;
    i_addr_l = 'b0;
    i_oe_l = 'b0;
    read_start = 1'b0;
    valid_kernel_data = 1'b0;
    i_nxt_state = IDLE;
    valid_data = 1'b0;
    start_fetching_store = 1'b0;
    casex (i_state)
      IDLE: begin
        ready_l = 1'b1;
        i_nxt_state = IDLE;
        if(start) begin
          ready_l = 1'b0;
          i_nxt_state = READY;
        end 
      end 
      READY: begin
        i_nxt_state = KERNEL_READ_DATA;
        i_CMD_l = CMD_READ;
        i_addr_l = 32'b0;
      end
      KERNEL_READ_DATA: begin
        read_start = 1'b1;
        i_nxt_state = KERNEL_READ_DATA;
        if(kernel_delay_counter >= 6) begin
          valid_kernel_data = 1'b1;
        end 
        if(kernel_delay_counter == BURST_SIZE-1) begin
          i_CMD_l = CMD_READ;
          i_addr_l = 32'h0000_0008;
          i_nxt_state = KERNEL_STORE_DATA;
        end
      end
      KERNEL_STORE_DATA: begin
        read_start = 1'b1;
        valid_kernel_data = 1'b1;
        i_nxt_state = KERNEL_STORE_DATA;
        if(kernel_delay_counter == BURST_SIZE-1) begin
          i_CMD_l = CMD_READ;
          i_addr_l = INITIAL_INPUT_ADDR;
        end
        if(kernel_row_counter == 1 && kernel_addr_counter == BURST_SIZE-1) begin
          valid_kernel_data = 1'b0;
          valid_data = 1'b1;
          i_nxt_state = DATA_STORE;
        end
      end
      DATA_STORE: begin
        i_nxt_state = DATA_STORE;
        read_start = 1'b1;
        valid_data = 1'b1;
        if(data_row_counter >= INITIAL_ROW_STORE && !data_row_counter[0] && data_column_counter == 0 && data_addr_counter == 0) begin
          start_fetching_store = 1'b1;
        end 

        if(data_row_counter == TOTAL_ROW-1 && data_column_counter == 0 && data_addr_counter == 0) begin
          start_fetching_store = 1'b1;
        end
        if(kernel_delay_counter == BURST_SIZE-1) begin
          i_CMD_l = CMD_READ;
          if(data_column_counter == 127) begin
            i_addr_l = INITIAL_INPUT_ADDR + ((data_row_counter + 1)<<LOG2_TOTAL_ROW);
          end else begin
            i_addr_l = INITIAL_INPUT_ADDR + ((data_row_counter) << LOG2_TOTAL_ROW) + ((data_column_counter + 1) << LOG2BURST_SIZE);
          end
          i_nxt_state = DATA_STORE;
          
          if(data_column_counter == 127 && data_row_counter == TOTAL_ROW-1) begin
            i_CMD_l = CMD_IDLE;
            i_nxt_state = DRAM_READ_WINDUP;
            read_start = 1'b0;
          end
        end
      end 
      DRAM_READ_WINDUP: begin
        valid_data = 1'b1;
        i_nxt_state = DRAM_READ_WINDUP;
        if(data_addr_counter == BURST_SIZE-1) begin
          valid_data = 1'b0;
          i_nxt_state = SRAM_READ_WINDUP;
        end
      end
      SRAM_READ_WINDUP: begin
        i_nxt_state = SRAM_READ_WINDUP;
        valid_data = 1'b0;
        if(final_output_address == FINAL_OUTPUT_ADDR && write_delay_counter == BURST_SIZE-1) begin
          i_nxt_state = IDLE;
        end
      end
      default: 
        i_nxt_state = IDLE;
    endcase
  end

endmodule