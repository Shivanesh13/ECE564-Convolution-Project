
`timescale 1ns/1ps
// optional: uncomment to catch undeclared nets
// `default_nettype none
module tri_state_driver (
    input  wire din,
    input  wire oe,
    inout  wire pad,
    output wire dout   // observed level on the pin
);
    assign pad  = oe ? din : 1'bz;
    assign dout = pad;
endmodule

