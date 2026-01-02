module dut #(
  parameter int ADDRESS_WIDTH = 32,
  parameter int DQ_WIDTH = 8
)(
  // System Signals
  input  wire                       clk,
  input  wire                       reset_n, 
 
  // Control signals
  input  wire                       start,
  output wire                       ready,


  // SDR memory interface
  output wire   [1:0]               input_CMD,  // 2'b00=IDLE, 2'b01=READ, 2'b10=WRITE
  output wire   [ADDRESS_WIDTH-1:0] input_addr,
  input  wire   [DQ_WIDTH-1:0]      input_dout,
  output wire   [DQ_WIDTH-1:0]      input_din,
  output wire                       input_oe,

  output wire   [1:0]               output_CMD,  // 2'b00=IDLE, 2'b01=READ, 2'b10=WRITE
  output wire   [ADDRESS_WIDTH-1:0] output_addr,
  input  wire   [DQ_WIDTH-1:0]      output_dout,
  output wire   [DQ_WIDTH-1:0]      output_din,
  output wire                       output_oe

);

 typedef enum bit [2:0] {IDLE,READY,KERNEL_READ_DATA,KERNEL_STORE_DATA,DATA_STORE,WINDUP} input_states;
 localparam BURST_SIZE = 8;
 localparam COLUMN_ADDR = 10'b00_0000_0111;

  input_states i_state, i_nxt_state;
  logic [1:0] i_CMD_ff, i_CMD_l, o__CMD_l, o__CMD_ff;
  logic ready_ff,ready_l,i_oe_ff,i_oe_l;
  logic [ADDRESS_WIDTH-1:0] i_addr_l, i_addr_ff;


  logic signed [7:0] sram_test1 [0:1023];
  logic signed [7:0] sram_test2 [0:1023];
  logic signed [7:0] sram_test3 [0:1023];

  logic signed [7:0] kernel_ram [0:15];

  logic read_start,kernel_row_counter,valid_kernel_data, valid_kernel_data_d,valid_data,valid_data_d;
  logic [2:0] kernel_delay_counter;
  logic [2:0] kernel_addr_counter,data_addr_counter;
  logic signed [DQ_WIDTH-1:0] i_dout;
  logic [6:0] data_column_counter;
  logic [9:0] data_row_counter, data_calculated_addr;
  logic [3:0] kernel_calculated_addr;

  logic signed [7:0] register [0:7];
  logic signed [7:0] temp_register [0:7];

  always_ff @(posedge clk) begin
    if(!reset_n) 
      i_state <= IDLE;
    else 
      i_state <= i_nxt_state;
  end
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
      i_oe_ff <= i_oe_l;
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
    end else begin
      valid_data_d <= valid_data;
      if(valid_data_d) begin
        data_addr_counter <= data_addr_counter + 1;
        if(data_addr_counter == 7) begin
          data_column_counter <= data_column_counter + 1;
          if(data_column_counter == 127) 
            data_row_counter <= data_row_counter + 1;
        end
        if(data_row_counter == 0) begin
          sram_test1[data_calculated_addr-data_addr_counter] <= i_dout;         
        end else if(data_row_counter == 1) begin
          sram_test2[data_calculated_addr-data_addr_counter] <= i_dout;
        end else if(data_row_counter == 2) begin 
          sram_test3[data_calculated_addr-data_addr_counter] <= i_dout;
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
        end
      end
      else begin
        data_addr_counter <= 'b0;
      end
    end
  end
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
            i_nxt_state = WINDUP;
            read_start = 1'b0;
          end
        end
      end 
      WINDUP: begin
        valid_data = 1'b1;
        i_nxt_state = WINDUP;
        if(data_addr_counter == 7) begin
          valid_data = 1'b0;
          i_nxt_state = IDLE;
        end
      end
      default: 
        i_nxt_state = IDLE;
    endcase
  end
endmodule
