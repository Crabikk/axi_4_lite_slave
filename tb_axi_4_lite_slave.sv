`timescale 1ns / 1ps

module tb_axi_4_lite_slave();
    localparam CLK_PERIOD = 10;
    localparam ADDRESS = 32;
    localparam DATA_WIDTH = 32;
    
    logic CLK;
    logic RESET;
    
    // Write Address Channel
    logic [ADDRESS-1:0] S_AWADDR;
    logic S_AWVALID;
    logic S_AWREADY;
    
    // Write Data Channel
    logic [DATA_WIDTH-1:0] S_WDATA;
    logic [3:0] S_WSTRB;
    logic S_WVALID;
    logic S_WREADY;
    
    // Write Response Channel
    logic S_BREADY;
    logic [1:0] S_BRESP;
    logic S_BVALID;  
    
    // Read Address Channel
    logic [ADDRESS-1:0] S_ARADDR;
    logic S_ARVALID;
    logic S_ARREADY;
    
    // Read Data Channel
    logic S_RREADY;
    logic [DATA_WIDTH-1:0] S_RDATA;
    logic [1:0] S_RRESP;
    logic S_RVALID;  
    
    // Clock generation
    always #(CLK_PERIOD/2) CLK = ~CLK;
    
    // Instantiate DUT
    axi_4_lite_slave #(
        .ADDRESS(ADDRESS),
        .DATA_WIDTH(DATA_WIDTH),
        .WRITE_QUEUE_DEPTH(4),
        .READ_QUEUE_DEPTH(4)
    ) dut (
        .CLK(CLK),
        .RESET(RESET),
        .S_AWADDR(S_AWADDR),
        .S_AWVALID(S_AWVALID),
        .S_AWREADY(S_AWREADY),
        .S_WDATA(S_WDATA),
        .S_WSTRB(S_WSTRB),
        .S_WVALID(S_WVALID),
        .S_WREADY(S_WREADY),
        .S_BREADY(S_BREADY),
        .S_BRESP(S_BRESP),
        .S_BVALID(S_BVALID),
        .S_ARADDR(S_ARADDR),
        .S_ARVALID(S_ARVALID),
        .S_ARREADY(S_ARREADY),
        .S_RREADY(S_RREADY),
        .S_RDATA(S_RDATA),
        .S_RRESP(S_RRESP),
        .S_RVALID(S_RVALID)
    );
    
    // Test tasks
    task automatic write_transaction(input [ADDRESS-1:0] addr, input [DATA_WIDTH-1:0] data, input [3:0] strb = 4'b1111);
        // Drive address channel
        S_AWADDR <= addr;
        S_AWVALID <= 1'b1;
        
        // Drive data channel
        S_WDATA <= data;
        S_WSTRB <= strb;
        S_WVALID <= 1'b1;
        
        // Wait for both handshakes
        @(posedge CLK);
        while (!(S_AWREADY && S_WREADY)) @(posedge CLK);
        
        // Clear address and data channels immediately after handshake
        S_AWADDR <= '0;
        S_AWVALID <= 1'b0;
        S_WDATA <= '0;
        S_WSTRB <= '0;
        S_WVALID <= 1'b0;
        
        // Wait for response
        S_BREADY <= 1'b1;
        @(posedge CLK);
        while (!S_BVALID) @(posedge CLK);
        
        // Check response
        if (S_BRESP != 2'b00) begin
            $display("[ERROR] At time %0t: Write transaction failed: RESP = %b", $time, S_BRESP);
        end else begin
            $display("[INFO] At time %0t: Write transaction completed successfully", $time);
        end
        
        S_BREADY <= 1'b0;
    endtask

    task automatic read_transaction(input [ADDRESS-1:0] addr, output [DATA_WIDTH-1:0] data);
        // Drive address channel
        S_ARADDR <= addr;
        S_ARVALID <= 1'b1;
        
        // Wait for ARREADY
        @(posedge CLK);
        while (!S_ARREADY) @(posedge CLK);
        
        // Clear address channel immediately after handshake
        S_ARADDR <= '0;
        S_ARVALID <= 1'b0;
        
        // Wait for read data
        S_RREADY <= 1'b1;
        @(posedge CLK);
        while (!S_RVALID) @(posedge CLK);
        
        // Get data
        data = S_RDATA;
        
        // Check response
        if (S_RRESP != 2'b00) begin
            $display("[ERROR] At time %0t: Read transaction failed: RESP = %b", $time, S_RRESP);
        end else begin
            $display("[INFO] At time %0t: Read transaction completed successfully", $time);
        end
        
        S_RREADY <= 1'b0;
    endtask
    
    // Variables for tests
    logic [DATA_WIDTH-1:0] read_data;
    
    initial begin
        // Initialize
        CLK = 0;
        RESET = 1;
        S_AWADDR = 0;
        S_AWVALID = 0;
        S_WDATA = 0;
        S_WSTRB = 0;
        S_WVALID = 0;
        S_BREADY = 0;
        S_ARADDR = 0;
        S_ARVALID = 0;
        S_RREADY = 0;
        
        $display("[INFO] At time %0t: Initialization complete", $time);
        
        // Reset
        #100;
        RESET = 0;
        @(posedge CLK);
        
        $display("[INFO] At time %0t: Starting tests", $time);
        
        // ============================================
        // 1. Basic operations
        // ============================================
        $display("\n[TEST 1] At time %0t: Basic operations", $time);
        
        // Write to register 0
        $display("[INFO] At time %0t: Writing 0x12345678 to register 0", $time);
        write_transaction(32'h0000_0000, 32'h12345678);
        
        // Read from register 0
        read_transaction(32'h0000_0000, read_data);
        $display("[INFO] At time %0t: Read from register 0: 0x%h", $time, read_data);
        
        if (read_data !== 32'h12345678) begin
            $display("[ERROR] At time %0t: Mismatch! Expected: 0x12345678, Got: 0x%h", $time, read_data);
        end else begin
            $display("[PASS] At time %0t: Basic write/read test passed", $time);
        end
        
        // Write to register 1 with byte enables
        $display("[INFO] At time %0t: Writing 0xAABBCCDD to register 1 with byte enable 0b1010", $time);
        write_transaction(32'h0000_0004, 32'hAABBCCDD, 4'b1010);
        
        // Read from register 1
        read_transaction(32'h0000_0004, read_data);
        $display("[INFO] At time %0t: Read from register 1: 0x%h", $time, read_data);
        
        // Wait a bit
        repeat(10) @(posedge CLK);
        
        // ============================================
        // 2. Back-to-back write 
        // ============================================
        $display("\n[TEST 2] At time %0t: Back-to-back write (sequential)", $time);
        
        // First transaction
        $display("[INFO] At time %0t: Starting first back-to-back write transaction", $time);
        write_transaction(32'h0000_0008, 32'hDEADBEEF);
        $display("[INFO] At time %0t: Transaction 1 completed", $time);
        
        // Second transaction
        $display("[INFO] At time %0t: Starting second back-to-back write transaction", $time);
        write_transaction(32'h0000_000C, 32'hCAFEBABE);
        $display("[INFO] At time %0t: Transaction 2 completed", $time);
        
        // Third transaction
        $display("[INFO] At time %0t: Starting third back-to-back write transaction", $time);
        write_transaction(32'h0000_0010, 32'hFEEDFACE);
        $display("[INFO] At time %0t: Transaction 3 completed", $time);
        
        // Fourth transaction
        $display("[INFO] At time %0t: Starting fourth back-to-back write transaction", $time);
        write_transaction(32'h0000_0014, 32'hBABEC0DE);
        $display("[INFO] At time %0t: Transaction 4 completed", $time);
        
        // Verify all writes
        $display("[INFO] At time %0t: Verifying back-to-back writes...", $time);
        
        read_transaction(32'h0000_0008, read_data);
        if (read_data !== 32'hDEADBEEF) begin
            $display("[ERROR] At time %0t: Register 2 mismatch: Expected 0xDEADBEEF, Got 0x%h", $time, read_data);
        end else begin
            $display("[PASS] At time %0t: Register 2 OK", $time);
        end
        
        read_transaction(32'h0000_000C, read_data);
        if (read_data !== 32'hCAFEBABE) begin
            $display("[ERROR] At time %0t: Register 3 mismatch: Expected 0xCAFEBABE, Got 0x%h", $time, read_data);
        end else begin
            $display("[PASS] At time %0t: Register 3 OK", $time);
        end
        
        read_transaction(32'h0000_0010, read_data);
        if (read_data !== 32'hFEEDFACE) begin
            $display("[ERROR] At time %0t: Register 4 mismatch: Expected 0xFEEDFACE, Got 0x%h", $time, read_data);
        end else begin
            $display("[PASS] At time %0t: Register 4 OK", $time);
        end
        
        read_transaction(32'h0000_0014, read_data);
        if (read_data !== 32'hBABEC0DE) begin
            $display("[ERROR] At time %0t: Register 5 mismatch: Expected 0xBABEC0DE, Got 0x%h", $time, read_data);
        end else begin
            $display("[PASS] At time %0t: Register 5 OK", $time);
        end
        
        $display("[PASS] At time %0t: Back-to-back write test completed", $time);
        
        // Wait a bit
        repeat(10) @(posedge CLK);
        
        // ============================================
        // 3. Back-to-back read 
        // ============================================
        $display("\n[TEST 3] At time %0t: Back-to-back read (sequential)", $time);
        
        // Send 4 write transactions quickly
        $display("[INFO] At time %0t: Starting 4 fast write transactions", $time);
        for (int i = 0; i < 4; i++) begin
            automatic int idx = i;
            // Send address
            @(posedge CLK);
            S_AWADDR <= 32'h0000_0030 + idx * 4;
            S_AWVALID <= 1'b1;
            
            // Send data
            S_WDATA <= 32'h600D_F00D + idx;
            S_WVALID <= 1'b1;
            S_WSTRB <= 4'b1111;
            
            // Wait for ready
            @(posedge CLK);
            while (!(S_AWREADY && S_WREADY)) @(posedge CLK);
            
            // Clear valid signals
            S_AWVALID <= 1'b0;
            S_WVALID <= 1'b0;
        end
        
        // Wait for all responses
        S_BREADY <= 1'b1;
        for (int i = 0; i < 4; i++) begin
            @(posedge CLK);
            while (!S_BVALID) @(posedge CLK);
            $display("[INFO] At time %0t: Got write response %0d: %b", $time, i, S_BRESP);
        end
        S_BREADY <= 1'b0;
        
        // Check written values
        $display("[INFO] At time %0t: Verifying written values...", $time);
        for (int i = 0; i < 4; i++) begin
            read_transaction(32'h0000_0030 + i * 4, read_data);
            if (read_data !== (32'h600D_F00D + i)) begin
                $display("[ERROR] At time %0t: Queue register %0d mismatch: Expected 0x%h, Got 0x%h", 
                         $time, i, 32'h600D_F00D + i, read_data);
            end else begin
                $display("[PASS] At time %0t: Queue register %0d OK", $time, i);
            end
        end
        
        $display("[PASS] At time %0t: Back-to-back read test completed", $time);

        // Wait a bit
        repeat(10) @(posedge CLK);
        
        // ============================================
        // 4. Fast transactions
        // ============================================
        $display("\n[TEST 4] At time %0t: Fast transactions", $time);

        fork
            begin
                $display("[INFO] At time %0t: Starting fast write transaction", $time);
                // Fast write (no additional delays between steps)
                S_AWADDR <= 32'h0000_0028;
                S_AWVALID <= 1'b1;
                S_WDATA <= 32'h55555555;
                S_WSTRB <= 4'b1111;
                S_WVALID <= 1'b1;
                
                // Wait for ready
                @(posedge CLK);
                while (!(S_AWREADY && S_WREADY)) @(posedge CLK);
                
                // Immediately clear valid signals
                S_AWADDR <= '0;
                S_AWVALID <= 1'b0;
                S_WDATA <= '0;
                S_WVALID <= 1'b0;
                S_WSTRB <= '0;
                
                // Wait for response
                S_BREADY <= 1'b1;
                @(posedge CLK);
                while (!S_BVALID) @(posedge CLK);
                S_BREADY <= 1'b0;
                
                $display("[INFO] At time %0t: Fast write completed", $time);
            end
            begin
                $display("[INFO] At time %0t: Starting fast read transaction", $time);
                // Fast read
                S_ARADDR <= 32'h0000_0010;
                S_ARVALID <= 1'b1;
                
                @(posedge CLK);
                while (!S_ARREADY) @(posedge CLK);
                
                S_ARADDR <= '0;
                S_ARVALID <= 1'b0;
                
                S_RREADY <= 1'b1;
                @(posedge CLK);
                while (!S_RVALID) @(posedge CLK);
                
                $display("[INFO] At time %0t: Fast read: 0x%h", $time, S_RDATA);
                S_RREADY <= 1'b0;
            end
        join

        // Wait a bit
        repeat(10) @(posedge CLK);

        // ============================================
        // 5. Error adress test
        // ============================================
        $display("\n[TEST 5] At time %0t: Address error", $time);
        
        // Send 4 write transactions quickly to fill queues
        $display("[INFO] At time %0t: Sending 4 write transactions to fill queues", $time);
        for (int i = 0; i < 1; i++) begin
            automatic int idx = i;
            // Send address
            S_AWADDR <= 32'h0000_1030 + idx * 4;
            S_AWVALID <= 1'b1;
            
            // Send data
            S_WDATA <= 32'h600D_F00D + idx;
            S_WVALID <= 1'b1;
            S_WSTRB <= 4'b1111;
            
            // Wait for ready
            @(posedge CLK);
            while (!(S_AWREADY && S_WREADY)) @(posedge CLK);
            
            // Clear valid signals
            S_AWVALID <= 1'b0;
            S_WVALID <= 1'b0;
        end
        
        // Wait for all responses
        S_BREADY <= 1'b1;
        for (int i = 0; i < 1; i++) begin
            @(posedge CLK);
            while (!S_BVALID) @(posedge CLK);
            $display("[INFO] At time %0t: Got write response %0d: %b", $time, i, S_BRESP);
        end
        S_BREADY <= 1'b0;
        
        // Check written values
        for (int i = 0; i < 1; i++) begin
            read_transaction(32'h0000_1030 + i * 4, read_data);
        end

	// Wait a bit
        repeat(10) @(posedge CLK)

	// ============================================
        // 6. Write and read at the same time
        // ============================================
        $display("\n[TEST 6] At time %0t: Write and read at the same time", $time);
        
	fork
		begin
			for (int i = 0; i < 4; i++) begin
			    automatic int idx = i;
			    // Send address
			    @(posedge CLK);
			    S_AWADDR <= 32'h0000_0030 + idx * 4;
			    S_AWVALID <= 1'b1;
			    
			    // Send data
			    S_WDATA <= 32'h600D_F01D + idx;
			    S_WVALID <= 1'b1;
			    S_WSTRB <= 4'b1111;
			    
			    // Wait for ready
			    @(posedge CLK);
			    while (!(S_AWREADY && S_WREADY)) @(posedge CLK);
			    
			    // Clear valid signals
			    S_AWVALID <= 1'b0;
			    S_WVALID <= 1'b0;
			end
			
			// Wait for all responses
			S_BREADY <= 1'b1;
			for (int i = 0; i < 4; i++) begin
			    @(posedge CLK);
			    while (!S_BVALID) @(posedge CLK);
			    $display("[INFO] At time %0t: Got write response %0d: %b", $time, i, S_BRESP);
			end
			S_BREADY <= 1'b0;
		end

		begin
			read_transaction(32'h0000_0008, read_data);
			read_transaction(32'h0000_000C, read_data);
			read_transaction(32'h0000_0010, read_data);
			read_transaction(32'h0000_0014, read_data);
		end
	join

        
        $display("[PASS] At time %0t: Back-to-back write test completed", $time);
        
        $display("\n[INFO] At time %0t: All tests completed", $time);
        
        // Wait a bit and finish
        repeat(100) @(posedge CLK);
        $display("[INFO] At time %0t: Simulation finished", $time);
        $finish;
    end
    
    // Timeout
    initial begin
        #1000000; // 1ms timeout
        $display("[ERROR] At time %0t: Simulation timeout!", $time);
        $finish;
    end
   
endmodule