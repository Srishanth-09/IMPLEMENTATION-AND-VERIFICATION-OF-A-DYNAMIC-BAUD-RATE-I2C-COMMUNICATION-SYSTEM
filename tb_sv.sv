timeunit 1ns/1ns;
timeprecision 1ns;

module tb_sv;

    // DUT interface
    logic        clk;
    logic        areset;
    logic [6:0]  addr;
    logic [7:0]  data_in;
    logic        rw;
    logic        enable;
    logic [7:0]  data_out;
    logic        busy;
    logic        scl;
    wire        sda;

    int error_count = 0;

    i2c_top_multi uut (
        .clk      (clk),
        .areset   (areset),
        .addr     (addr),
        .data_in  (data_in),
        .rw       (rw),
        .enable   (enable),
        .data_out (data_out),
        .busy     (busy),
        .scl      (scl),
        .sda      (sda)
    );

    // 100 MHz clock
    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // I2C protocol check tasks
    // ------------------------------------------------------------

    // START: SDA goes low while SCL is high
    task automatic i2c_check_start();
        @(negedge sda);
        if (scl !== 1'b1) begin
            $error("[%0t] START condition violated: SDA fell while SCL != 1", $time);
            error_count++;
        end else begin
            $display("[%0t] START condition OK", $time);
        end
    endtask

    // STOP: SDA goes high while SCL is high
    task automatic i2c_check_stop();
        @(posedge sda);
        if (scl !== 1'b1) begin
            $error("[%0t] STOP condition violated: SDA rose while SCL != 1", $time);
            error_count++;
        end else begin
            $display("[%0t] STOP condition OK", $time);
        end
    endtask

    // Address phase: 7-bit address + R/W, then ACK/NACK
    task automatic i2c_check_address_and_ack(
        input logic [6:0] exp_addr,
        input logic       exp_rw
    );
        int i;
        logic [7:0] addr_byte;

        // 8 bits: [7:1] address, [0] R/W, MSB first
        for (i = 7; i >= 0; i--) begin
            @(posedge scl);
            addr_byte[i] = sda;
        end

        if (addr_byte[7:1] !== exp_addr || addr_byte[0] !== exp_rw) begin
            $error("[%0t] Address/RW mismatch. Got %b (addr=%b, rw=%0b), expected addr=%b, rw=%0b",
                   $time, addr_byte, addr_byte[7:1], addr_byte[0], exp_addr, exp_rw);
            error_count++;
        end else begin
            $display("[%0t] Address phase OK: addr=%b, rw=%0b",
                     $time, addr_byte[7:1], addr_byte[0]);
        end

        // ACK/NACK from slave (9th clock)
        @(posedge scl);
        if (sda !== 1'b0) begin
            $error("[%0t] Expected ACK after address, but got NACK/high", $time);
            error_count++;
        end else begin
            $display("[%0t] ACK received after address", $time);
        end
    endtask

    // Data write: 1 data byte from master + ACK from slave
    task automatic i2c_check_data_write_and_ack(
        input logic [7:0] exp_data
    );
        int i;
        logic [7:0] data_byte;

        // 8 data bits, MSB first
        for (i = 7; i >= 0; i--) begin
            @(posedge scl);
            data_byte[i] = sda;
        end

        if (data_byte !== exp_data) begin
            $error("[%0t] Data write mismatch. Got %b, expected %b",
                   $time, data_byte, exp_data);
            error_count++;
        end else begin
            $display("[%0t] Data write OK: %b", $time, data_byte);
        end

        // ACK/NACK from slave (9th clock)
        @(posedge scl);
        if (sda !== 1'b0) begin
            $error("[%0t] Expected ACK after data byte, but got NACK/high", $time);
            error_count++;
        end else begin
            $display("[%0t] ACK received after data byte", $time);
        end
    endtask

    // Simple read transaction checker (focus on ACKs & continuity)
    // Here we just ensure each read byte is followed by an ACK/NACK.
    task automatic i2c_check_data_read(
        output logic [7:0] read_data
    );
        int i;
        logic [7:0] data_byte;

        for (i = 7; i >= 0; i--) begin
            @(posedge scl);
            data_byte[i] = sda;
        end

        read_data = data_byte;
        $display("[%0t] Data read from bus: %b", $time, read_data);

        // ACK/NACK from master for read byte (depends on protocol usage)
        @(posedge scl);
        $display("[%0t] After read byte, SDA=%b (ACK=0, NACK=1, depends on your design)",
                 $time, sda);
    endtask

    // ------------------------------------------------------------
    // Optional baud-rate test helper (hook this to your DUT)
    // ------------------------------------------------------------
    task automatic set_baud(input int baud_id);
        // NOTE:
        //  - Hook this to your DUT's baud-rate control (parameter or register)
        //  - Example if DUT had 'baud_sel' input:
        //      uut.baud_sel = baud_id;
        $display("[%0t] [BAUD] Switching baud selector to %0d (hook to DUT manually)",
                 $time, baud_id);
        #1000; // allow some settling time if needed
    endtask

    // One combined write + read sequence for reuse (for baud tests too)
    task automatic write_then_read(
        input  logic [6:0] slv_addr,
        input  logic [7:0] write_data,
        input  logic [7:0] exp_read_data,
        input  string      tag
    );
        logic [7:0] read_from_bus;

        $display("\n--- %s: WRITE & READ: SLAVE (addr=%b) ---", tag, slv_addr);

        // ---------------- WRITE CYCLE ----------------
        addr   = slv_addr;
        data_in = write_data;
        rw      = 1'b0;   // write
        enable  = 1'b1;

        i2c_check_start();
        i2c_check_address_and_ack(addr, rw);
        i2c_check_data_write_and_ack(write_data);
        i2c_check_stop();

        wait (!busy);
        enable = 1'b0;
        #500;

        // ---------------- READ CYCLE -----------------
        rw      = 1'b1;   // read
        enable  = 1'b1;

        i2c_check_start();
        i2c_check_address_and_ack(addr, rw);
        i2c_check_data_read(read_from_bus);
        i2c_check_stop();

        wait (!busy);
        enable = 1'b0;
        #500;

        $display("%s: Data Read: %b (Expected %b)", tag, data_out, exp_read_data);
        if (data_out !== exp_read_data) begin
            $error("[%0t] %s: data_out mismatch, got %b, expected %b",
                   $time, tag, data_out, exp_read_data);
            error_count++;
        end
    endtask

    // ------------------------------------------------------------
    // Main stimulus
    // ------------------------------------------------------------
    initial begin
        clk     = 0;
        areset  = 1;
        addr    = '0;
        data_in = '0;
        rw      = 0;
        enable  = 0;

        #100;
        areset = 0;

        // --------------------------------------------------------
        // Basic functional + protocol tests (single baud)
        // --------------------------------------------------------

        // Slave 1
        write_then_read(7'b1010111, 8'b10101010, 8'b11001101, "SLAVE 1");

        // Slave 2
        write_then_read(7'b1011000, 8'b11110000, 8'b11110000, "SLAVE 2");

        // Slave 3
        write_then_read(7'b1011001, 8'b00111100, 8'b00111100, "SLAVE 3");

        // --------------------------------------------------------
        // Multiple baud-rate + adaptive baud tests
        // (You MUST connect 'set_baud' to your DUT's baud control)
        // --------------------------------------------------------

        $display("\n=== MULTIPLE BAUD RATE TESTS ===");

        // Example: "baud_id" could correspond to standard/divider settings
        set_baud(0);
        write_then_read(7'b1011000, 8'hAA, 8'hAA, "BAUD0_SLAVE2");

        set_baud(1);
        write_then_read(7'b1011000, 8'h55, 8'h55, "BAUD1_SLAVE2");

        // Adaptive change: switch baud between transactions
        $display("\n=== ADAPTIVE BAUD TEST: CHANGE BAUD DURING RUN ===");
        set_baud(2);
        write_then_read(7'b1010111, 8'hCC, 8'hCC, "BAUD2_SLAVE1");

        set_baud(0);
        write_then_read(7'b1010111, 8'h0F, 8'h0F, "BAUD0_SLAVE1_AGAIN");

        #1000;

        if (error_count == 0)
            $display("\nSimulation Complete! ALL CHECKS PASSED ?");
        else
            $display("\nSimulation Complete! %0d ERRORS detected ?", error_count);

        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("tb_sv.vcd");
        $dumpvars(0, tb_sv);
    end

endmodule
