`timescale 1ns / 1ps

module axi_4_lite_slave #(
    parameter ADDRESS = 32,
    parameter DATA_WIDTH = 32,
    parameter WRITE_QUEUE_DEPTH = 4,
    parameter READ_QUEUE_DEPTH = 1
) (
    input                       CLK,
    input                       RESET,
    
    // Write Address Channel
    input      [ADDRESS-1:0]    S_AWADDR,
    input                       S_AWVALID,
    output logic                S_AWREADY,
    
    // Write Data Channel
    input     [DATA_WIDTH-1:0]  S_WDATA,
    input      [3:0]            S_WSTRB,
    input                       S_WVALID,
    output logic                S_WREADY,
    
    // Write Response Channel
    input                       S_BREADY,
    output logic     [1:0]      S_BRESP,
    output logic                S_BVALID,
    
    // Read Address Channel
    input      [ADDRESS-1:0]    S_ARADDR,
    input                       S_ARVALID,
    output logic                S_ARREADY,
    
    // Read Data Channel
    input                       S_RREADY,
    output logic [DATA_WIDTH-1:0] S_RDATA,
    output logic     [1:0]      S_RRESP,
    output logic                S_RVALID
);

    localparam NO_OF_REGISTERS = 32;
    localparam REG_ADDR_WIDTH = $clog2(NO_OF_REGISTERS);
    localparam BYTES_PER_REGISTER = DATA_WIDTH/8;
    
    logic [DATA_WIDTH-1:0] registers [0:NO_OF_REGISTERS-1];
    
    logic aw_addr_valid;
    logic ar_addr_valid;
    logic [REG_ADDR_WIDTH-1:0] aw_reg_index_raw;
    logic [REG_ADDR_WIDTH-1:0] ar_reg_index_raw;
    
    assign aw_addr_valid = (S_AWADDR[1:0] == 2'b00) && 
                          (S_AWADDR < (NO_OF_REGISTERS * BYTES_PER_REGISTER));
    assign ar_addr_valid = (S_ARADDR[1:0] == 2'b00) && 
                          (S_ARADDR < (NO_OF_REGISTERS * BYTES_PER_REGISTER));
    
    assign aw_reg_index_raw = S_AWADDR[REG_ADDR_WIDTH+1:2];
    assign ar_reg_index_raw = S_ARADDR[REG_ADDR_WIDTH+1:2];
    
    typedef struct packed {
        logic [ADDRESS-1:0] addr;
        logic [DATA_WIDTH-1:0] data;
        logic [3:0] strb;
        logic error;
        logic [REG_ADDR_WIDTH-1:0] reg_index;
    } write_transaction_t;
    
    write_transaction_t write_queue [0:WRITE_QUEUE_DEPTH-1];
    logic [$clog2(WRITE_QUEUE_DEPTH):0] write_queue_count;
    logic [$clog2(WRITE_QUEUE_DEPTH)-1:0] write_queue_wr_ptr;
    logic [$clog2(WRITE_QUEUE_DEPTH)-1:0] write_queue_rd_ptr;
    
    typedef struct packed {
        logic [ADDRESS-1:0] addr;
        logic error;
        logic [REG_ADDR_WIDTH-1:0] reg_index;
        logic valid;
    } read_transaction_t;
    
    read_transaction_t read_queue_reg;
    
    logic write_queue_full;
    logic write_queue_empty;
    
    assign write_queue_full = (write_queue_count == WRITE_QUEUE_DEPTH);
    assign write_queue_empty = (write_queue_count == 0);
    
    logic aw_handshake;
    logic w_handshake;
    logic write_queued;
    logic ar_handshake;
    
    logic read_bypass_enabled;
    logic [DATA_WIDTH-1:0] bypass_read_data;
    logic [1:0] bypass_read_resp;
    
    typedef enum logic [1:0] {
        WR_IDLE,
        WR_PROCESS,
        WR_RESPONSE
    } write_process_state_t;
    
    write_process_state_t write_process_state, write_process_state_next;
    
    typedef enum logic {
        RD_IDLE,
        RD_SEND
    } read_state_t;
    
    read_state_t read_state, read_state_next;
    
    logic [1:0] write_response_reg;
    
    assign aw_handshake = S_AWVALID && S_AWREADY;
    assign w_handshake = S_WVALID && S_WREADY;
    assign ar_handshake = S_ARVALID && S_ARREADY;
    
    assign S_AWREADY = !write_queue_full;
    assign S_WREADY = !write_queue_full;
    
    assign S_ARREADY = !read_queue_reg.valid || (S_RVALID && S_RREADY);
    
    assign write_queued = aw_handshake && w_handshake;
    assign read_bypass_enabled = !read_queue_reg.valid && ar_handshake;
    
    always_comb begin
        if (ar_addr_valid) begin
            bypass_read_data = registers[ar_reg_index_raw];
            bypass_read_resp = 2'b00;
        end else begin
            bypass_read_data = '0;
            bypass_read_resp = 2'b10;
        end
    end
    
    always_ff @(posedge CLK) begin
        if (RESET) begin
            for (int i = 0; i < NO_OF_REGISTERS; i++) begin
                registers[i] <= '0;
            end
        end else if (write_process_state_next == WR_PROCESS && !write_queue_empty) begin
            if (!write_queue[write_queue_rd_ptr].error) begin
                for (int i = 0; i < 4; i++) begin
                    if (write_queue[write_queue_rd_ptr].strb[i]) begin
                        registers[write_queue[write_queue_rd_ptr].reg_index][i*8 +: 8] <= 
                            write_queue[write_queue_rd_ptr].data[i*8 +: 8];
                    end
                end
            end
        end
    end
    
    always_ff @(posedge CLK) begin
        if (RESET) begin
            write_queue_count <= 0;
            write_queue_wr_ptr <= 0;
            write_queue_rd_ptr <= 0;
            for (int i = 0; i < WRITE_QUEUE_DEPTH; i++) begin
                write_queue[i] <= '0;
            end
        end else begin
            if (write_queued && !write_queue_full) begin
                write_queue[write_queue_wr_ptr].addr <= S_AWADDR;
                write_queue[write_queue_wr_ptr].data <= S_WDATA;
                write_queue[write_queue_wr_ptr].strb <= S_WSTRB;
                write_queue[write_queue_wr_ptr].reg_index <= aw_reg_index_raw;
                write_queue[write_queue_wr_ptr].error <= ~aw_addr_valid;
                
                write_queue_wr_ptr <= write_queue_wr_ptr + 1;
                write_queue_count <= write_queue_count + 1;
            end
            
            if ((write_process_state == WR_RESPONSE) && S_BVALID && S_BREADY && !write_queue_empty) begin
                write_queue_rd_ptr <= write_queue_rd_ptr + 1;
                write_queue_count <= write_queue_count - 1;
            end
        end
    end
    
    always_comb begin
        write_process_state_next = write_process_state;
        write_response_reg = 2'b00;
        
        case (write_process_state)
            WR_IDLE: begin
                if (!write_queue_empty) begin
                    write_process_state_next = WR_PROCESS;
                end
            end
            
            WR_PROCESS: begin
                if (!write_queue_empty) begin
                    if (!write_queue[write_queue_rd_ptr].error) begin
                        write_response_reg = 2'b00;
                    end else begin
                        write_response_reg = 2'b10;
                    end
                    
                    write_process_state_next = WR_RESPONSE;
                end else begin
                    write_process_state_next = WR_IDLE;
                end
            end
            
            WR_RESPONSE: begin
                if (S_BVALID && S_BREADY) begin
                    if (!write_queue_empty) begin
                        write_process_state_next = WR_PROCESS;
                    end else begin
                        write_process_state_next = WR_IDLE;
                    end
                end
            end
        endcase
    end
    
    always_ff @(posedge CLK) begin
        if (RESET) begin
            write_process_state <= WR_IDLE;
            S_BVALID <= 1'b0;
            S_BRESP <= 2'b00;
        end else begin
            write_process_state <= write_process_state_next;
            
            case (write_process_state_next)
                WR_RESPONSE: begin
                    S_BVALID <= 1'b1;
                    S_BRESP <= write_response_reg;
                end
                
                default: begin
                    if (S_BVALID && S_BREADY) begin
                        S_BVALID <= 1'b0;
                    end
                end
            endcase
        end
    end
    
    always_ff @(posedge CLK) begin
        if (RESET) begin
            read_queue_reg <= '0;
            read_state <= RD_IDLE;
            S_RVALID <= 1'b0;
            S_RDATA <= '0;
            S_RRESP <= 2'b00;
        end else begin
            read_state <= read_state_next;
            
            if (read_bypass_enabled) begin
                S_RVALID <= 1'b1;
                S_RDATA <= bypass_read_data;
                S_RRESP <= bypass_read_resp;
                read_state <= RD_SEND;
            end 
            else if (read_state == RD_SEND) begin
                if (S_RREADY) begin
                    S_RVALID <= 1'b0;
                    read_queue_reg.valid <= 1'b0;
                    read_state <= RD_IDLE;
                end
            end 
            else if (ar_handshake && !read_queue_reg.valid) begin
                read_queue_reg.addr <= S_ARADDR;
                read_queue_reg.reg_index <= ar_reg_index_raw;
                read_queue_reg.error <= ~ar_addr_valid;
                read_queue_reg.valid <= 1'b1;
                
                S_RVALID <= 1'b1;
                S_RRESP <= (~ar_addr_valid) ? 2'b10 : 2'b00;
                S_RDATA <= (ar_addr_valid) ? registers[ar_reg_index_raw] : '0;
                read_state <= RD_SEND;
            end
        end
    end
    
    always_comb begin
        read_state_next = read_state;
        
        case (read_state)
            RD_IDLE: begin
                if (read_queue_reg.valid || ar_handshake) begin
                    read_state_next = RD_SEND;
                end
            end
            
            RD_SEND: begin
                if (S_RREADY) begin
                    read_state_next = RD_IDLE;
                end
            end
        endcase
    end
    
endmodule