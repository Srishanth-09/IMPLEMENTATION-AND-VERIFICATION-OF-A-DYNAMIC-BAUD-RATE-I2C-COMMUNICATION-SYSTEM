module i2c_top_multi (
    input clk,
    input areset,
    input [6:0] addr,
    input [7:0] data_in,
    input rw,
    input enable,
    output [7:0] data_out,
    output busy,
    output scl,
    inout sda
);

    // Master
    i2c_master master_inst (
        .clk(clk),
        .areset(areset),
        .addr(addr),
        .data_in(data_in),
        .rw(rw),
        .enable(enable),
        .data_out(data_out),
        .busy(busy),
        .scl(scl),
        .sda(sda)
    );

    // Slave 1 - address 1010111
    i2c_slave #(
        .SLAVE_ADDRESS(7'b1010111),
        .SLAVE_DATA(8'b11001101)
    ) slave1 (
        .scl(scl),
        .sda(sda)
    );

    // Slave 2 - address 1011000
    i2c_slave #(
        .SLAVE_ADDRESS(7'b1011000),
        .SLAVE_DATA(8'b11110000)
    ) slave2 (
        .scl(scl),
        .sda(sda)
    );

    // Slave 3 - address 1011001
    i2c_slave #(
        .SLAVE_ADDRESS(7'b1011001),
        .SLAVE_DATA(8'b00111100)
    ) slave3 (
        .scl(scl),
        .sda(sda)
    );
endmodule

