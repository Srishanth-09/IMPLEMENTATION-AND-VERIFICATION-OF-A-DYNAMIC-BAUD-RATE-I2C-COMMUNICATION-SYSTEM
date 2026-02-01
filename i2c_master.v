module i2c_master(
    input clk,            // main 100MHz clock
    input areset,         // asynchronous reset
    input [6:0] addr,     // address of slave device
    input [7:0] data_in,  // data to write
    input enable,         // enable for i2c master
    input rw,             // high for read, low for write
    output reg [7:0] data_out, // output data after read
    output busy,          // high when busy
    output scl,           // serial clock line
    inout sda             // serial data line
);

    parameter IDLE = 3'b000,
              START = 3'b001,
              ADDR = 3'b010,
              READ_ACK_1 = 3'b011,
              DATA_TRANS = 3'b100,
              WRITE_ACK = 3'b101,
              READ_ACK_2 = 3'b110,
              STOP = 3'b111;

    reg [2:0] state = IDLE;
    reg [2:0] count = 0;
    reg [7:0] count_2 = 0;
    reg i2c_clk = 0;
    reg [7:0] saved_addr;
    reg [7:0] saved_data;
    reg sda_out;
    reg sda_enable = 0;
    reg scl_enable = 0;
    reg [7:0] scl_divider;
    reg [7:0] active_divider;

    // =======================
    // Dynamic Clock Divider
    // =======================
    always @(*) begin
        case (addr)
            7'b1010111: scl_divider = 124; // 100 kHz
            7'b1011000: scl_divider = 62;  // 200 kHz
            7'b1011001: scl_divider = 31;  // 400 kHz
            default:    scl_divider = 124; // Default
        endcase
    end

    always @(posedge clk or posedge areset) begin
        if (areset)
            active_divider <= 124;
        else if (enable)
            active_divider <= scl_divider; // lock divider per transaction
    end

    always @(posedge clk) begin
        if (count_2 >= active_divider) begin
            i2c_clk <= ~i2c_clk;
            count_2 <= 0;
        end else begin
            count_2 <= count_2 + 1;
        end
    end

    // =======================
    // I2C State Machine
    // =======================
    always @(posedge i2c_clk or posedge areset) begin
        if(areset)
            state <= IDLE;
        else begin
            case(state)
                IDLE: if(enable) begin
                          state <= START;
                          saved_addr <= {addr, rw};
                          saved_data <= data_in;
                      end
                START: begin state <= ADDR; count <= 7; end
                ADDR:  if(count==0) state <= READ_ACK_1; else count <= count-1;
                READ_ACK_1: if(sda==0) begin count <= 7; state <= DATA_TRANS; end
                             else state <= STOP;
                DATA_TRANS: begin
                    if(saved_addr[0]) begin
                        data_out[count] <= sda;
                        if(count==0) state <= WRITE_ACK;
                        else count <= count-1;
                    end else begin
                        if(count==0) state <= READ_ACK_2;
                        else count <= count-1;
                    end
                end
                WRITE_ACK: state <= STOP;
                READ_ACK_2: if(sda==0 && enable==1) state <= IDLE; else state <= STOP;
                STOP: state <= IDLE;
            endcase
        end
    end

    always @(negedge i2c_clk or posedge areset) begin
        if(areset) begin
            sda_out <= 1;
            sda_enable <= 1;
        end else begin
            case(state)
                START: begin sda_out <= 0; sda_enable <= 1; end
                ADDR: begin sda_out <= saved_addr[count]; sda_enable <= 1; end
                READ_ACK_1: sda_enable <= 0;
                DATA_TRANS: begin
                    if(saved_addr[0]) sda_enable <= 0;
                    else begin sda_out <= saved_data[count]; sda_enable <= 1; end
                end
                WRITE_ACK: begin sda_out <= 0; sda_enable <= 1; end
                READ_ACK_2: sda_enable <= 0;
                STOP: begin sda_out <= 1; sda_enable <= 1; end
            endcase
        end
    end

    assign scl = (state == IDLE || state == START || state == STOP) ? 1'b1 : i2c_clk;
    assign sda = (sda_enable) ? sda_out : 1'bz;
    assign busy = (state == IDLE) ? 0 : 1;
endmodule
