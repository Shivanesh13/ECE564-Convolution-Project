
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
  output   wire  [SRAM_ADDRESS_WIDTH-1 :0] read_address  ,
  input  wire  [SRAM_DATA_WIDTH-1 :0]    read_data     ,
  output   wire                            read_enable   , 
  
  //---------------------------------------------------------------
  // Port B: Write Port 
  output   wire  [SRAM_ADDRESS_WIDTH-1 :0] write_address ,
  output   wire  [SRAM_DATA_WIDTH-1 :0]    write_data    ,
  output   wire                            write_enable          


);

 typedef enum logic [2:0] {IDLE,READY,KERNEL_READ_DATA,KERNEL_STORE_DATA,DATA_STORE,DRAM_READ_WINDUP,SRAM_READ_WINDUP} input_states;
 typedef enum logic [2:0] {WAIT,SRAM_READ0,SRAM_READ1,SRAM_WRITE} control_states;
 typedef enum logic [2:0] {WAIT_M,INITIAL_LOAD,LOAD0,LOAD1} multi_states;
 typedef enum logic [1:0] {READ_00,READ_01,READ_10,READ_11} sram_read_op;
 
 localparam BURST_SIZE = 8;
 localparam COLUMN_ADDR = 10'b00_0000_0111;

  control_states c_state,c_nxt_state;
  multi_states m_state, m_nxt_state;
  input_states i_state, i_nxt_state;
  logic [1:0] i_CMD_ff, i_CMD_l, o__CMD_l, o__CMD_ff;
  logic ready_ff,ready_l,i_oe_ff,i_oe_l;
  logic [DRAM_ADDRESS_WIDTH-1:0] i_addr_l, i_addr_ff;

  logic signed [7:0] kernel_ram [0:15];

  logic read_start,kernel_row_counter,valid_kernel_data, valid_kernel_data_d,valid_data,valid_data_d;
  logic [2:0] kernel_delay_counter;
  logic [2:0] kernel_addr_counter,data_addr_counter;
  logic signed [DRAM_DQ_WIDTH-1:0] i_dout;
  logic [6:0] data_column_counter;
  logic [9:0] data_row_counter, kernel_calculated_addr, data_calculated_addr;

  logic signed [7:0] register [0:7];
  logic signed [7:0] temp_register [0:7];
  logic signed [7:0] main_register [0:10];


  logic signed [19:0] M00, M01, M02, M03, M10, M11, M12, M13, M20, M21, M22, M23, M30, M31, M32, M33;
  logic signed [19:0] A0, A1, A2, A3, S;

  logic [SRAM_ADDRESS_WIDTH-1:0] sram_pointer;
  logic valid_sram_initialize,begin_computation,begin_computation_d,begin_rewrite,begin_rewrite_d;
  logic [1:0] s_row_counter;
  logic [7:0] s_colm_counter;

  logic signed [SRAM_ADDRESS_WIDTH - 1: 0] sram_write_addr, sram_read_addr,sram_initialize_read_addr,sram_addr_counter,sram_addr0_ini,sram_addr1_ini,sram_addr2_ini;
  logic signed [SRAM_DATA_WIDTH - 1: 0] sram_read_data, sram_write_data,sram_temp_write;
  logic sram_read_enable, sram_write_enable, start_fetching;

  logic signed [SRAM_DATA_WIDTH - 1: 0] temp_sram_buff0_0 [0:2];
  logic signed [SRAM_DATA_WIDTH - 1: 0] temp_sram_buff0_1 [0:2];
  logic signed [2*SRAM_DATA_WIDTH + 24 - 1: 0] main_sram_buff  [0:2];

  logic [2:0] fetch_counter,compute_counter;
  logic valid_sram_initialize_d,valid_sram_initialize_2d,shift_left,valid_computation;
  sram_read_op read_op,read_op_d,read_op_2d;
  logic [1:0] sram_temp_addr,sram_temp_addr_d,sram_temp_addr_2d;
  logic extend_read;


  always_ff @(posedge clk) begin
    if(!reset_n) begin
      i_state <= IDLE;
      c_state <= WAIT;
      m_state <= WAIT_M;
    end
    else begin
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


  // Input States Values: 
  assign ready = ready_ff;
  assign input_CMD = i_CMD_ff;
  assign input_addr = i_addr_ff;
  assign input_oe = i_oe_ff;

  assign kernel_calculated_addr = (kernel_row_counter << 3) | (COLUMN_ADDR);
  assign data_calculated_addr = (data_column_counter << 3) | (COLUMN_ADDR);

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
        if(kernel_addr_counter == 7) begin
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

  always_ff @(posedge clk) begin
    if(!reset_n) begin
      valid_data_d <= 'b0;
      data_row_counter <= 'b0;
      data_column_counter <= 'b0;
      data_addr_counter <= 'b0;
      begin_rewrite_d <= 'b0;
      s_row_counter <= 'b0;
      s_colm_counter <= 'b0;
      extend_read <= 'b0;
    end else begin
      valid_data_d <= valid_data;
      begin_rewrite_d <= begin_rewrite;
      
      if(valid_data_d) begin
        data_addr_counter <= data_addr_counter + 1;
        if(data_addr_counter == 7) begin
          data_column_counter <= data_column_counter + 1;
          if(data_column_counter == 127) 
            data_row_counter <= data_row_counter + 1;
        end

        if(data_row_counter <= 2) begin
          if(data_addr_counter == 3 || data_addr_counter == 7) begin
            sram_write_addr <= (data_row_counter << 8) + ((data_calculated_addr-data_addr_counter) >> 2);
            sram_write_data <= {i_dout,sram_temp_write[31:8]};
            sram_temp_write <= {i_dout,sram_temp_write[31:8]};
            sram_write_enable <= 1'b1;
          end else begin
            sram_temp_write <= {i_dout,sram_temp_write[31:8]};
            sram_write_enable <= 1'b0;
          end         
        end else begin
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
          end

          if(begin_rewrite) begin
            sram_write_enable <= 1'b1;
            sram_write_addr <= (s_row_counter*256 + s_colm_counter)%12'h300;
            sram_write_data <= {i_dout,temp_register[1],temp_register[2],temp_register[3]};
            s_colm_counter <= s_colm_counter + 1;
            begin_computation <= 1'b1;
          end else if(begin_rewrite_d) begin
            begin_computation <= 1'b0;
            sram_write_enable <= 1'b1;
            s_colm_counter <= s_colm_counter + 1;
            sram_write_addr <= (s_row_counter*256 + s_colm_counter)%12'h300;
            sram_write_data <= {register[4],register[5],register[6],register[7]};
            if(s_colm_counter == 255) begin
              s_row_counter <= (s_row_counter + 1)%3;
            end
          end
          else begin
            begin_computation <= 1'b0;
            sram_write_enable <= 1'b0;
          end
        end
      end
      else begin
        sram_write_enable <= 1'b0;
        data_addr_counter <= 'b0;
        begin_computation <= 1'b0;
      end
    end
  end

  logic valid_computation_d;
  logic signed [7:0] return_val;


  always_ff @(posedge clk ) begin
    if(!reset_n) begin
      compute_counter <= 'b0;
      valid_computation_d <= 'b0;
    end else begin
      valid_computation_d <= valid_computation;
      if(valid_computation) begin
        A0 <= M00 + M10 + M20 + M30;
        A1 <= M01 + M11 + M21 + M31;
        A2 <= M02 + M12 + M22 + M32;
        A3 <= M03 + M13 + M23 + M33;
      end
      if(valid_computation_d) begin
        S <= A0 + A1 + A2 + A3;
      end

      if(S > 127) return_val <= 127;
      else if(S < -128) return_val <= -128;
      else return_val <= S;


      if(begin_computation) begin
        compute_counter <= 'b0;
        if(m_state == WAIT_M ) begin
          main_sram_buff[0] <= {temp_sram_buff0_0[0],temp_sram_buff0_1[0],24'b0};
          main_sram_buff[1] <= {temp_sram_buff0_0[1],temp_sram_buff0_1[1],24'b0};
          main_sram_buff[2] <= {temp_sram_buff0_0[2],temp_sram_buff0_1[2],24'b0};
          main_register[0] <= register[0];
          main_register[1] <= register[1];
          main_register[2] <= register[2];
          main_register[3] <= register[3];
          main_register[4] <= register[4];
          main_register[5] <= register[5];
          main_register[6] <= register[6];
          main_register[7] <= register[7];
        end else begin
          main_sram_buff[0] <= {main_sram_buff[0][79:56],temp_sram_buff0_0[0],temp_sram_buff0_1[0]};
          main_sram_buff[1] <= {main_sram_buff[1][79:56],temp_sram_buff0_0[1],temp_sram_buff0_1[1]};
          main_sram_buff[2] <= {main_sram_buff[2][79:56],temp_sram_buff0_0[2],temp_sram_buff0_1[2]};
          main_register[0] <= main_register[1];
          main_register[1] <= main_register[2];
          main_register[2] <= main_register[3];
          main_register[3] <= register[0];
          main_register[4] <= register[1];
          main_register[5] <= register[2];
          main_register[6] <= register[3];
          main_register[7] <= register[4];
          main_register[8] <= register[5];
          main_register[9] <= register[6];
          main_register[10] <= register[7];

        end
      end else if(shift_left && (m_state == INITIAL_LOAD || m_state == LOAD1)) begin
        main_sram_buff[0] <= main_sram_buff[0] << 8;
        main_sram_buff[1] <= main_sram_buff[1] << 8;
        main_sram_buff[2] <= main_sram_buff[2] << 8;
        main_register[0]  <= main_register[1];
        main_register[1]  <= main_register[2];
        main_register[2]  <= main_register[3];
        main_register[3]  <= main_register[4];
        main_register[4]  <= main_register[5];
        main_register[5]  <= main_register[6];
        main_register[6]  <= main_register[7];
        main_register[7]  <= main_register[8];
        main_register[8]  <= main_register[9];
        main_register[9]  <= main_register[10];
        main_register[10] <= 'b0;
        compute_counter <= compute_counter + 1;
      end
      else 
        compute_counter <= compute_counter + 1;
    end
  end

  logic signed [7:0] source_data [0:15];

  assign source_data[0]  = main_sram_buff[0][87:80];
  assign source_data[1]  = main_sram_buff[0][79:72];
  assign source_data[2]  = main_sram_buff[0][71:64];
  assign source_data[3]  = main_sram_buff[0][63:56];
  assign source_data[4]  = main_sram_buff[1][87:80];
  assign source_data[5]  = main_sram_buff[1][79:72];
  assign source_data[6]  = main_sram_buff[1][71:64];
  assign source_data[7]  = main_sram_buff[1][63:56];
  assign source_data[8]  = main_sram_buff[2][87:80];
  assign source_data[9]  = main_sram_buff[2][79:72];
  assign source_data[10] = main_sram_buff[2][71:64];
  assign source_data[11] = main_sram_buff[2][63:56];
  assign source_data[12] = main_register[0];
  assign source_data[13] = main_register[1];
  assign source_data[14] = main_register[2];
  assign source_data[15] = main_register[3];


  always_comb begin
    valid_computation = 1'b0;
    shift_left = 1'b0;
    casex (m_state)
      WAIT_M: begin
        m_nxt_state = WAIT_M;
        if(begin_computation) begin
          m_nxt_state = INITIAL_LOAD;
        end
      end
      INITIAL_LOAD: begin
        m_nxt_state = INITIAL_LOAD;
        valid_computation = 1'b0;
        shift_left = 1'b0;
        if(begin_computation) begin
          m_nxt_state = LOAD1;
        end
        casex (compute_counter) 
          0: begin
            valid_computation = 1'b1;
            shift_left = 1'b1;
            M00 = kernel_ram[0]  * source_data[0] ;
            M01 = kernel_ram[1]  * source_data[1] ;
            M02 = kernel_ram[2]  * source_data[2] ;
            M03 = kernel_ram[3]  * source_data[3] ;
            M10 = kernel_ram[4]  * source_data[4] ;
            M11 = kernel_ram[5]  * source_data[5] ;
            M12 = kernel_ram[6]  * source_data[6] ;
            M13 = kernel_ram[7]  * source_data[7] ;
            M20 = kernel_ram[8]  * source_data[8] ;
            M21 = kernel_ram[9]  * source_data[9] ;
            M22 = kernel_ram[10] * source_data[10];
            M23 = kernel_ram[11] * source_data[11];
            M30 = kernel_ram[12] * source_data[12];
            M31 = kernel_ram[13] * source_data[13];
            M32 = kernel_ram[14] * source_data[14];
            M33 = kernel_ram[15] * source_data[15];
          end 
        1,2,3,4: begin
            shift_left = 1'b1;
            if(compute_counter == 4)
              shift_left = 1'b0;
            valid_computation = 1'b1;
            M00 = kernel_ram[0]  * source_data[0] ;
            M01 = kernel_ram[1]  * source_data[1] ;
            M02 = kernel_ram[2]  * source_data[2] ;
            M03 = kernel_ram[3]  * source_data[3] ;
            M10 = kernel_ram[4]  * source_data[4] ;
            M11 = kernel_ram[5]  * source_data[5] ;
            M12 = kernel_ram[6]  * source_data[6] ;
            M13 = kernel_ram[7]  * source_data[7] ;
            M20 = kernel_ram[8]  * source_data[8] ;
            M21 = kernel_ram[9]  * source_data[9] ;
            M22 = kernel_ram[10] * source_data[10];
            M23 = kernel_ram[11] * source_data[11];
            M30 = kernel_ram[12] * source_data[12];
            M31 = kernel_ram[13] * source_data[13]; 
            M32 = kernel_ram[14] * source_data[14]; 
            M33 = kernel_ram[15] * source_data[15]; 
        end
          default: begin
            shift_left = 1'b0;
            valid_computation = 1'b0;
          end
        endcase
      end
      LOAD0: begin
        if(begin_computation) begin
          m_nxt_state = LOAD1;
          valid_computation = 1'b0;
        end
      end
      LOAD1: begin
        m_nxt_state = LOAD1;
        shift_left = 1'b1;
        valid_computation = 1'b1;
        M00 = kernel_ram[0]  * source_data[0] ;
        M01 = kernel_ram[1]  * source_data[1] ;
        M02 = kernel_ram[2]  * source_data[2] ;
        M03 = kernel_ram[3]  * source_data[3] ;
        M10 = kernel_ram[4]  * source_data[4] ;
        M11 = kernel_ram[5]  * source_data[5] ;
        M12 = kernel_ram[6]  * source_data[6] ;
        M13 = kernel_ram[7]  * source_data[7] ;
        M20 = kernel_ram[8]  * source_data[8] ;
        M21 = kernel_ram[9]  * source_data[9] ;
        M22 = kernel_ram[10] * source_data[10];
        M23 = kernel_ram[11] * source_data[11];
        M30 = kernel_ram[12] * source_data[12];
        M31 = kernel_ram[13] * source_data[13];
        M32 = kernel_ram[14] * source_data[14];
        M33 = kernel_ram[15] * source_data[15];
        
        // if(compute_counter == 7) begin
        //   m_nxt_state = LOAD0;
        // end
      end
      default: m_nxt_state = WAIT_M;
    endcase
  end

 logic [10:0] read_counter;
 logic sram_read_op_complete;


  always_ff @(posedge clk) begin
    if(!reset_n) begin
      sram_addr_counter <= 'b0;
      sram_addr0_ini <= 'b0;
      sram_addr1_ini <= 256;
      sram_addr2_ini <= 512;
      fetch_counter <= 'b0;
      sram_temp_addr_d <= 'b0;
      sram_temp_addr_2d <= 'b0;
      valid_sram_initialize_d <= 'b0;
      valid_sram_initialize_2d <= 'b0;
      sram_read_enable <= 1'b0;
      read_op_2d <= READ_00;
      read_op_d <= READ_00;
      begin_rewrite <= 'b0;
      read_counter <= 'b0;
    end else begin
      sram_temp_addr_2d <= sram_temp_addr_d;
      valid_sram_initialize_d <= valid_sram_initialize;
      valid_sram_initialize_2d <= valid_sram_initialize_d;
      read_op_d <= read_op;
      read_op_2d <= read_op_d;
      sram_temp_addr_d <= sram_temp_addr;

      if(start_fetching) begin
        fetch_counter <= 1;
      end else begin
        fetch_counter <= fetch_counter + 1;
      end

      if(valid_sram_initialize == 1'b1) begin
        if(sram_temp_addr == 2) begin
          sram_addr_counter <= sram_addr_counter + 1;
        end
        sram_read_enable <= 1'b1;
        sram_read_addr <= sram_pointer;
      end else begin
        sram_read_enable <= 1'b0;
        sram_read_addr <= 'b0;
      end

      if(sram_pointer[7:0] == 8'hff && fetch_counter == 6)begin
        if(read_counter == 0) begin
          read_counter <= 3;
        end else begin
          read_counter <= read_counter + 1;
        end
      end

      if(valid_sram_initialize_2d) begin
        if(read_op_2d == READ_00) begin
          temp_sram_buff0_0[sram_temp_addr_2d] <= sram_read_data;
            begin_rewrite <= 1'b0;
        end else if(read_op_2d == READ_01) begin
          if(sram_temp_addr_2d == 2) 
            begin_rewrite <= 1'b1;
          else 
            begin_rewrite <= 1'b0;
          temp_sram_buff0_1[sram_temp_addr_2d] <= sram_read_data;
        end else if(read_op_2d == READ_10) begin
          temp_sram_buff0_0[sram_temp_addr_2d] <= sram_read_data;
          begin_rewrite <= 1'b0;
        end else if(read_op_2d == READ_11) begin
          if(sram_temp_addr_2d == 2) 
            begin_rewrite <= 1'b1;
          else 
            begin_rewrite <= 1'b0;
          temp_sram_buff0_1[sram_temp_addr_2d] <= sram_read_data;
        end
      end
      else begin
        begin_rewrite <= 1'b0;
      end
    end
  end

 

  always_comb begin
    c_nxt_state = WAIT;
    sram_pointer = 'b0;
    valid_sram_initialize = 'b0;
    sram_temp_addr = 'b0;
    sram_read_op_complete = 1'b0;
    casex (c_state)
      WAIT: begin
        if(start_fetching) begin
          c_nxt_state = SRAM_READ0;
        end
      end 
      SRAM_READ0: begin
        c_nxt_state = SRAM_READ0;
        casex (fetch_counter)
          1: begin
            valid_sram_initialize = 1'b1;
            read_op = READ_00;
            sram_pointer = (sram_addr_counter + sram_addr0_ini)%12'h300;
            sram_temp_addr = 0;
          end 
          2: begin
            valid_sram_initialize = 1'b1;
            read_op = READ_00;
            sram_pointer = (sram_addr_counter + sram_addr1_ini)%12'h300;
            sram_temp_addr = 1;
          end
          3: begin
            valid_sram_initialize = 1'b1;
            read_op = READ_00;
            sram_pointer = (sram_addr_counter + sram_addr2_ini)%12'h300;
            sram_temp_addr = 2;
          end
          4: begin
            valid_sram_initialize = 1'b1;
            read_op = READ_01;
            sram_pointer = (sram_addr_counter + sram_addr0_ini)%12'h300;
            sram_temp_addr = 0;
          end
          5: begin
            valid_sram_initialize = 1'b1;
            read_op = READ_01;
            sram_pointer = (sram_addr_counter + sram_addr1_ini)%12'h300;
            sram_temp_addr = 1;
          end

          6: begin
            valid_sram_initialize = 1'b1;
            read_op = READ_01;
            sram_pointer = (sram_addr_counter + sram_addr2_ini)%12'h300;
            sram_temp_addr = 2;
          end
          7: begin
            valid_sram_initialize = 1'b0;
            read_op = READ_10;
            c_nxt_state = SRAM_READ1;
          end
          default: begin
            if(read_counter == 1023) begin
              c_nxt_state = WAIT;
              sram_read_op_complete = 1'b1;
            end
            valid_sram_initialize = 1'b0;
          end
        endcase
      end
      SRAM_READ1: begin
        c_nxt_state = SRAM_READ1;
        casex (fetch_counter)
          1: begin
            valid_sram_initialize = 1'b1;
            read_op = READ_10;
            sram_pointer = (sram_addr_counter + sram_addr0_ini)%12'h300;
            sram_temp_addr = 0;
          end 
          2: begin
            valid_sram_initialize = 1'b1;
            read_op = READ_10;
            sram_pointer = (sram_addr_counter + sram_addr1_ini)%12'h300;
            sram_temp_addr = 1;
          end
          3: begin
            valid_sram_initialize = 1'b1;
            read_op = READ_10;
            sram_pointer = (sram_addr_counter + sram_addr2_ini)%12'h300;
            sram_temp_addr = 2;
          end
          4: begin
            valid_sram_initialize = 1'b1;
            read_op = READ_11;
            sram_pointer = (sram_addr_counter + sram_addr0_ini)%12'h300;
            sram_temp_addr = 0;
          end
          5: begin
            valid_sram_initialize = 1'b1;
            read_op = READ_11;
            sram_pointer = (sram_addr_counter + sram_addr1_ini)%12'h300;
            sram_temp_addr = 1;
          end
          6: begin
            valid_sram_initialize = 1'b1;
            read_op = READ_11;
            sram_pointer = (sram_addr_counter + sram_addr2_ini)%12'h300;
            sram_temp_addr = 2;
          end
          7: begin
            valid_sram_initialize = 1'b0;
            read_op = READ_11;
            c_nxt_state = SRAM_READ0;
          end
          default: begin
            if(read_counter == 1023) begin
              c_nxt_state = WAIT;
              sram_read_op_complete = 1'b1;
            end
            valid_sram_initialize = 1'b0;
          end
        endcase
      end
      default: begin
        c_nxt_state = WAIT;
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
    start_fetching = 1'b0;
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
        i_CMD_l = 2'b01;
        i_addr_l = 32'b0;
      end
      KERNEL_READ_DATA: begin
        read_start = 1'b1;
        i_nxt_state = KERNEL_READ_DATA;
        if(kernel_delay_counter >= 6) begin
          valid_kernel_data = 1'b1;
        end 
        if(kernel_delay_counter == 7) begin
          i_CMD_l = 2'b01;
          i_addr_l = 32'h0000_0008;
          i_nxt_state = KERNEL_STORE_DATA;
        end
      end
      KERNEL_STORE_DATA: begin
        read_start = 1'b1;
        valid_kernel_data = 1'b1;
        i_nxt_state = KERNEL_STORE_DATA;
        if(kernel_delay_counter == 7) begin
          i_CMD_l = 2'b01;
          i_addr_l = 32'h0000_0010;
        end
        if(kernel_row_counter == 1 && kernel_addr_counter == 7) begin
          valid_kernel_data = 1'b0;
          valid_data = 1'b1;
          i_nxt_state = DATA_STORE;
        end
      end
      DATA_STORE: begin
        i_nxt_state = DATA_STORE;
        read_start = 1'b1;
        valid_data = 1'b1;
        if(data_row_counter == 2 && data_column_counter == 127 && data_addr_counter == 6) begin
          start_fetching = 1'b1;
        end
        if(kernel_delay_counter == 7) begin
          i_CMD_l = 2'b01;
          if(data_column_counter == 127) begin
            i_addr_l = 32'h0000_0010 + ((data_row_counter + 1)<<10);
          end else begin
            i_addr_l = 32'h0000_0010 + ((data_row_counter) << 10) + ((data_column_counter + 1) << 3);
          end
          i_nxt_state = DATA_STORE;
          
          if(data_column_counter == 127 && data_row_counter == 1023) begin
            i_CMD_l = 2'b00;
            i_nxt_state = DRAM_READ_WINDUP;
            read_start = 1'b0;
          end
        end
      end 
      DRAM_READ_WINDUP: begin
        valid_data = 1'b1;
        i_nxt_state = DRAM_READ_WINDUP;
        if(data_addr_counter == 7) begin
          valid_data = 1'b0;
          i_nxt_state = SRAM_READ_WINDUP;
        end
      end
      SRAM_READ_WINDUP: begin
        i_nxt_state = IDLE;
        valid_data = 1'b0;
        if(sram_read_op_complete) begin
          i_nxt_state = IDLE;
        end
      end
      default: 
        i_nxt_state = IDLE;
    endcase
  end

endmodule
