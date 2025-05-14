module ExceptionHandler
#(  parameter CSR_ADDR_MSTATUS = 12'h300, 
    parameter CSR_ADDR_MIE     = 12'h304, 
    parameter CSR_ADDR_MTVEC   = 12'h305, 
    parameter CSR_ADDR_MEPC    = 12'h341, 
    parameter CSR_ADDR_MCAUSE  = 12'h342, 
    parameter CSR_ADDR_MIP     = 12'h344 )
(
    input  wire        clk,
    input  wire        rst,

    // ----------  EXCEPCIÓN ----------
    input  wire        exception,        //determinar si hay excepción o no
    input  wire        mret,             //señal que notifica si terminó la rutina de manejo de excepciones
    input  wire [31:0] mcause_in,        //Código de la causa de excepción o interrupción
    input  wire [31:0] pc_actual,        //PC actual que se almacenará en mepc

    // ----------  INSTRUCCIÓN CSR ----------
    input  wire        csr_op_valid,     // llega una instrucción a ejecutar
    input  wire [2:0]  csr_op_type,      // 0=read,1=CSRRW,2=CSRRS,3=CSRRC
    input  wire [11:0] csr_op_addr,      //dirección del CSR
    input  wire [31:0] csr_op_wdata,     //rs1 o inmediato de la instrucción
    output wire [31:0] csr_op_rdata,     //Dato que se lee de los CSRs
    output wire        csr_op_done,      //Indica si terminó la instrucción CSR
	 
	 // --------------- Salidas para el procesador -----------------
	 output reg [31:0] mtvec_vect_out,  // dirección ISR calculada
	 output reg [31:0] mepc_out,         // PC de retorno

    // ----------  MONITOREO DE MANEJO DE EXCEPCIÓN ----------
    output reg         exception_handling_flag //Se mantiene en 1 mientras se maneja la excepción o interrupción
);

    // ------------------------------------------------------------------------
    //  Señales hacia CSRFile
    // ------------------------------------------------------------------------
    reg  [11:0] csr_addr;       //dirección del CSR con el que se va a interactuar
    reg  [31:0] csr_wdata;      //Valor para la instrucción CSRRW
    reg         csr_write;      //hay instrucción CSRRW/WI a ejecutar
    reg  [31:0] csr_set;        //Valor para la instrucción CSRRS/SI
    reg         csr_set_valid;  //hay instrucción CSRRS/SI a ejecutar
    reg  [31:0] csr_clear;      //Valor para la instrucción CSRRC/CI
    reg         csr_clear_valid;//hay instrucción CSRRC/CI a ejecutar
    wire [31:0] csr_rdata;      //Valor leído multiplexado de CSR

    // ------------------------------------------------------------------------
    //  Salidas directas de CSRFile
    // ------------------------------------------------------------------------
    wire [31:0] mstatus, mie, mtvec, mepc, mcause, mip;

    // ------------------------------------------------------------------------
    //  Registros para exponer valor leído y pulso “done”
    // ------------------------------------------------------------------------
    reg [31:0] csr_op_rdata_reg;   ///revisar
    reg        csr_op_done_reg;
    assign csr_op_rdata = csr_op_rdata_reg;
    assign csr_op_done  = csr_op_done_reg;

    // ----------------- variables auxiliares --------------------
    reg [1:0] prep_step;   // 0,1,2  (sub-pasos de PREPARE)
    reg       prep_done;   // 1 -> pasamos a HANDLE
    // -----------------------------------------------------------

    // ------------------------------------------------------------------------
    //  Instancia de CSRFile
    // ------------------------------------------------------------------------
    CSRFile u_csrfile (
        .clk            (clk),
        .rst            (rst),
        .csr_addr       (csr_addr),
        .csr_wdata      (csr_wdata),
        .csr_write      (csr_write),
        .csr_set        (csr_set),
        .csr_set_valid  (csr_set_valid),
        .csr_clear      (csr_clear),
        .csr_clear_valid(csr_clear_valid),
        .csr_rdata      (csr_rdata),
        .mstatus        (mstatus),
        .mie            (mie),
        .mtvec          (mtvec),
        .mepc           (mepc),
        .mcause         (mcause),
        .mip            (mip)
    );

    // ------------------------------------------------------------------------
    //  Máquina de estados
    // ------------------------------------------------------------------------
    parameter  IDLE       = 3'b000,
               PREPARE    = 3'b001,
               HANDLE     = 3'b010,
               RESTORE    = 3'b011,
               CSR_ACCESS = 3'b100;

    reg [2:0] current_state, next_state;

    // Registro de estado  (reset ACTIVO-BAJO)
    always @(posedge clk or negedge rst) begin
        if (!rst) 
            current_state <= IDLE;
        else     
            current_state <= next_state;
    end

    // ------------------------------------------------------------------------
    //  Transiciones de estados
    // ------------------------------------------------------------------------
    always @(*) begin
        case (current_state)
            IDLE: begin
                if (exception)
                    next_state = PREPARE;
                else if (csr_op_valid)
                    next_state = CSR_ACCESS;
                else
                    next_state = IDLE;
            end
            PREPARE:    next_state = prep_done ? HANDLE : PREPARE;
            HANDLE:     next_state = mret ? RESTORE : HANDLE;
            RESTORE:    next_state = IDLE;
            CSR_ACCESS: next_state = IDLE;
            default:    next_state = IDLE;
        endcase
    end

    // ------------------------------------------------------------------------
    //  Lógica secuencial principal
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            // --------- RESET de todos los registros -------------------------
            csr_addr         <= 12'h0;
            csr_wdata        <= 32'h0;
            csr_write        <= 1'b0;
            csr_set          <= 32'h0;
            csr_set_valid    <= 1'b0;
            csr_clear        <= 32'h0;
            csr_clear_valid  <= 1'b0;
            csr_op_rdata_reg <= 32'h0;
            csr_op_done_reg  <= 1'b0;
            exception_handling_flag <= 1'b0;
            prep_step        <= 2'd0;
            prep_done        <= 1'b0;
				mtvec_vect_out  <= 32'h0;   // reset nuevas salidas
            mepc_out        <= 32'h0;
        end else begin
            // -------- valores POR DEFECTO cada ciclo ------------------------
            csr_addr         <= 12'h0;
            csr_wdata        <= 32'h0;
            csr_write        <= 1'b0;
            csr_set          <= 32'h0;
            csr_set_valid    <= 1'b0;
            csr_clear        <= 32'h0;
            csr_clear_valid  <= 1'b0;
            csr_op_rdata_reg <= 32'h0;   
            csr_op_done_reg  <= 1'b0;
				mtvec_vect_out  <= 32'h0;   // se “tapan” salvo en PREPARE
            mepc_out        <= 32'h0;
            prep_done        <= 1'b0;    // ← se levantará sólo al terminar PREPARE
            // ----------------------------------------------------------------

            case (current_state)
                //───────────────────────────────────────────────────────────
                PREPARE: begin
                    case (prep_step)
                        /* Paso 0 : escribir MCAUSE */
                        2'd0: begin
                            csr_addr  <= CSR_ADDR_MCAUSE;
                            csr_wdata <= mcause_in;
                            csr_write <= 1'b1;
									 mtvec_vect_out <= (mtvec[0])      ?   // MODE=1 → vectored
                                              ({mtvec[31:2],2'b00} + (mcause_in << 2)) :
                                              {mtvec[31:2],2'b00};  // MODE=0 → direct
                            prep_step <= 2'd1;
                        end
                        /* Paso 1 : escribir MEPC */
                        2'd1: begin
                            csr_addr  <= CSR_ADDR_MEPC;
                            csr_wdata <= pc_actual;
                            csr_write <= 1'b1;
                            prep_step <= 2'd2;
									 mepc_out  <= pc_actual;
                        end
                        /* Paso 2 : actualizar MSTATUS  (MPIE←MIE, MIE←0) */
                        2'd2: begin
                            csr_addr  <= CSR_ADDR_MSTATUS;
                            csr_wdata <= { mstatus[31:8],        // bits 31:8 sin cambio
                                           mstatus[3],           // bit 7 (MPIE) ← antiguo MIE
                                           mstatus[6:4],         // bits 6:4 sin cambio
                                           1'b0,                 // bit 3 (MIE)  ← 0
                                           mstatus[2:0] };       // bits 2:0 sin cambio
                            csr_write <= 1'b1;
                            prep_step <= 2'd0;   // resetea sub-contador
                            prep_done <= 1'b1;   // avisa que PREPARE terminó
                        end
                    endcase
                end
                //───────────────────────────────────────────────────────────
                HANDLE: begin
                    exception_handling_flag <= 1'b1;
                    //Rutinas de manejo de excepciones o interrupciones en SW
                end
                //───────────────────────────────────────────────────────────
                RESTORE: begin
                    exception_handling_flag <= 1'b0;
                    // Restaurar MIE = MPIE y poner MPIE=1 según la spec
                    csr_addr  <= CSR_ADDR_MSTATUS;
                    csr_wdata <= { mstatus[31:8],
                                   1'b1,                 // MPIE ← 1
                                   mstatus[6:4],
                                   mstatus[7],           // MIE  ← antiguo MPIE
                                   mstatus[2:0] };
                    csr_write <= 1'b1;
                end
                //───────────────────────────────────────────────────────────
                CSR_ACCESS: begin
                    csr_addr <= csr_op_addr;
                    case (csr_op_type)
                        3'd1: begin                     // CSRRW/CSRRWI
                            csr_write <= 1'b1;
                            csr_wdata <= csr_op_wdata;
                        end
                        3'd2: begin                     // CSRRS/CSRRSI
                            csr_set_valid <= 1'b1;
                            csr_set       <= csr_op_wdata;
                        end
                        3'd3: begin                     // CSRRC/CSRRCI
                            csr_clear_valid <= 1'b1;
                            csr_clear       <= csr_op_wdata;
                        end
                        //default: ;                      // lectura pura
                    endcase

                    // si era lectura, capturamos
                    if (csr_op_type == 3'd0)
                        csr_op_rdata_reg <= csr_rdata;

                    csr_op_done_reg <= 1'b1; // pulso de fin
                end
                //───────────────────────────────────────────────────────────
            endcase
        end
    end
endmodule