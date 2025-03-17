/*
    apb_peripheral - Source Code for APB Peripheral

    ECE 571 - Team 6 Winter 2025
*/

module apb_peripheral
# (parameter numWS = 0)
(
    apb_if.peripheral apb  // Connect to APB interface (peripheral side)
);
  // Import package
  import apb_pkg::*; 

  // FSM Variables
  state currState, nextState;
  logic [5:0] wsCount, nextwsCount;

  // Internal storage (simple 4-register memory)
  logic [31:0] reg_mem[REG_ITEMS];

  // FSM
  always_ff @(posedge apb.pclk or negedge apb.presetn) begin
    if (!apb.presetn) begin
      // Reset internal registers
      foreach (reg_mem[i]) begin
        reg_mem[i] <= '0;  // Set each element to 0
      end

      // Reset status registers
      currState <= IDLE;

      // Reset counter
      wsCount <= '0;
    end else begin
      // Push next state to current state
      currState <= nextState;

      // Update counter
      wsCount <= nextwsCount;
    end
  end

  assign nextwsCount =  (currState != SETUP) ? numWS :  
                        (|wsCount) ? wsCount - 1: wsCount;

  // Output Logic
  always_comb begin
    unique case (currState)
      // For any other state, don't send data yet
      IDLE, ACCESS, ERROR: begin
        apb.prdata = 'bz;
        apb.pready = 1'b0;
        apb.pslverr = 1'b0;
      end
      SETUP: begin
        // Write operation
        if (apb.pwrite) begin
          apb.prdata = 'bz;
        // For read transfer, drive PRDATA with the contents of reg_mem using PADDR
        end else begin
          apb.prdata = (nextState == ERROR) ? 'bz : reg_mem[apb.paddr[ADDR_WIDTH-1:ALIGNBITS]];
        end

        // Simulate waitstates and handle PREADY
        apb.pready = (nextState == ACCESS || nextState == ERROR) ? 1'b1 : 1'b0;
        apb.pslverr = (nextState == ERROR) ? 1'b1 : 1'b0;
      end
    endcase
  end

  // Next State Logic
  always_comb begin
    unique case (currState)
      // IDLE: Default state of APB Protocol (no transfer)
      IDLE: begin
        if (apb.psel) begin
          nextState = SETUP;
        end else begin
          nextState = IDLE;
        end
      end

      // SETUP: Transfer initiated
      SETUP: begin
        if (wsCount == 0) begin
          nextState = ACCESS;
        end else begin
          nextState = SETUP;
        end

        // Check errors in the SETUP state
        if (!apb.psel || !validAlign(apb.paddr) || !apb.penable || getPprot(apb.paddr) !== apb.pprot) 
          nextState = ERROR;  // Go to ERROR state
      end

      // ACCESS: Handles chained accesses and transitions back to IDLE or SETUP
      ACCESS: begin
        if (apb.psel) begin
          nextState = SETUP;
        end else begin
          nextState = IDLE;
        end
      end

      // ERROR: Invalid transfer detected, return to IDLE
      ERROR: begin
        nextState = IDLE;
      end
    endcase
  end

endmodule
