module CSRFile (
    input             clk,
    input             rst,

    input      [11:0] csr_addr,       // dirección del CSR
    input      [31:0] csr_wdata,      // rs1  (para CSRRW / CSRRWI)
    input             csr_write,      // 1 = CSRRW / CSRRWI

    input      [31:0] csr_set,        // rs1  (para CSRRS / CSRRSI)
    input             csr_set_valid,  // 1 = CSRRS / CSRRSI

    input      [31:0] csr_clear,      // rs1  (para CSRRC / CSRRCI)
    input             csr_clear_valid,// 1 = CSRRC / CSRRCI

    output reg [31:0] csr_rdata,      // lectura combinacional

    // ---------- salidas directas ----------
    output reg [31:0] mstatus,  // 0x300
    output reg [31:0] mie,      // 0x304
    output reg [31:0] mtvec,    // 0x305
    output reg [31:0] mepc,     // 0x341
    output reg [31:0] mcause,   // 0x342
    output reg [31:0] mip       // 0x344
);
    // ---------------- escritura sincrónica ----------------
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            mstatus <= 32'h0;
            mie     <= 32'h0;
            mtvec   <= 32'h0;
            mepc    <= 32'h0;
            mcause  <= 32'h0;
            mip     <= 32'h0;
        end else begin
            // CSRRW / CSRRWI -------------------------------------------------
            if (csr_write) begin
                case (csr_addr)
                    12'h300: mstatus <= csr_wdata;
                    12'h304: mie     <= csr_wdata;
                    12'h305: mtvec   <= csr_wdata;
                    12'h341: mepc    <= csr_wdata;
                    12'h342: mcause  <= csr_wdata;
                    12'h344: mip     <= csr_wdata;
                    default: ;
                endcase
            end
            // CSRRS / CSRRSI -------------------------------------------------
            else if (csr_set_valid) begin
                case (csr_addr)
                    12'h300: mstatus <= mstatus | csr_set;
                    12'h304: mie     <= mie     | csr_set;
                    12'h344: mip     <= mip     | csr_set;
                    default: ;
                endcase
            end
            // CSRRC / CSRRCI -------------------------------------------------
            else if (csr_clear_valid) begin
                case (csr_addr)
                    12'h300: mstatus <= mstatus & ~csr_clear;
                    12'h304: mie     <= mie     & ~csr_clear;
                    12'h344: mip     <= mip     & ~csr_clear;
                    default: ;
                endcase
            end
        end
    end

    // ---------------- lectura combinacional ---------------
    always @(*) begin
        case (csr_addr)
            12'h300: csr_rdata = mstatus;
            12'h304: csr_rdata = mie;
            12'h305: csr_rdata = mtvec;
            12'h341: csr_rdata = mepc;
            12'h342: csr_rdata = mcause;
            12'h344: csr_rdata = mip;
            default: csr_rdata = 32'h0;
        endcase
    end
endmodule
