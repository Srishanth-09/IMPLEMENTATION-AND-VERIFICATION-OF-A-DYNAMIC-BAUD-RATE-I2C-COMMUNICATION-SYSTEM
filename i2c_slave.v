module i2c_slave #(
    parameter SLAVE_ADDRESS = 7'b1010111,
    parameter SLAVE_DATA = 8'b11001101
)(
    input scl,
    inout sda
);

    localparam READ_ADDR=2'b00, SEND_ACK_1=2'b01, DATA_TRANS=2'b10, SEND_ACK_2=2'b11;

    reg [1:0] state=READ_ADDR;
    reg [6:0] addr;
    reg rw;
    reg [7:0] data_in=0;
    reg [7:0] data_out=SLAVE_DATA;
    reg sda_out=0;
    reg sda_enable=0;
    reg sda_enable_2=1;
    reg [2:0] count=7;
    reg start=0;
    reg stop=1;

    always @(sda) begin
        if (sda==0 && scl==1) begin
            start <= 1; stop <= 0;
        end
        if (sda==1 && scl==1) begin
            start <= 0; stop <= 1;
        end
    end

    always @(posedge scl) begin
        if (start) begin
            case(state)
                READ_ADDR: begin
                    if (count==0) begin
                        sda_enable_2 <= 1;
                        rw <= sda;
                        state <= SEND_ACK_1;
                    end else begin
                        addr[count-1] <= sda;
                        count <= count - 1;
                    end
                end
                SEND_ACK_1: begin
                    if (addr == SLAVE_ADDRESS) begin
                        state <= DATA_TRANS;
                        count <= 7;
                    end
                    else  begin 
                        count <= 7;
                        state <= READ_ADDR;
                    
                    end
                end
                DATA_TRANS: begin
                    
                        data_in[count] <= sda;
                        if (count==0) state <= SEND_ACK_2;
                        else count <= count - 1;
                   
                end
                SEND_ACK_2: begin
                    state <= READ_ADDR;
                    sda_enable_2 <= 0;
                    count <= 7;
                end
            endcase
        end else if (stop) begin
            state <= READ_ADDR;
            sda_enable_2 <= 1;
            count <= 7;
        end
    end

    always @(negedge scl) begin
        case(state)
            READ_ADDR: sda_enable <= 0;
            SEND_ACK_1: begin
                if (addr == SLAVE_ADDRESS) begin
                    sda_out <= 0;
                    sda_enable <= 1;
                end else sda_enable <= 0;
            end
            DATA_TRANS: begin
                if (!rw)
                    sda_enable <= 0;
                else begin
                    sda_out <= data_out[count];
                    sda_enable <= 1;
                end
            end
            SEND_ACK_2: begin
                sda_out <= 0;
                sda_enable <= 1;
            end
        endcase
    end

    assign sda = (sda_enable && sda_enable_2) ? sda_out : 1'bz;
endmodule