
module sram1r1w
    #(
      parameter ADDR_WIDTH = 10,
      parameter DATA_WIDTH = 32 
    )
    (
      //---------------------------------------------------------------
      // General
      clk        ,    

      //---------------------------------------------------------------
      // Port A: Read Port 
      addra       ,
      read_data   ,
      ena         , 
      
      //---------------------------------------------------------------
      // Port B: Write Port 
      addrb       ,
      write_data  ,
      web          
    );


  input   wire                        clk;

  input   wire  [ADDR_WIDTH-1 :0]     addra;
  output  wire  [DATA_WIDTH-1 :0]     read_data;
  input   wire                        ena; 

  input   wire  [ADDR_WIDTH-1 :0]     addrb;
  input   wire  [DATA_WIDTH-1 :0]     write_data;
  input   wire                        web; 

  reg  [DATA_WIDTH-1 :0] mem     [1<<ADDR_WIDTH] ;

  reg  [DATA_WIDTH-1 :0] reg_read_data;
  reg                    reg_ena; 

  always @(posedge clk)
    begin
      reg_ena  <=   ena; 
    end

  always @(posedge clk)
    begin
      reg_read_data   <= ( reg_ena ) ? mem [addra] : 
                                reg_read_data ;
    end

  always @(posedge clk)
    begin
      if (web)
        mem [addrb] <= write_data ;
    end

  assign read_data = reg_read_data  ;


endmodule


