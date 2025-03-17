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

  // Internal storage
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
        // TODO: Need write logic here
        if (apb.pwrite) begin
          apb.prdata = 'bz;

        // For read transfer, drive PRDATA with the contents
        // of the reg_mem using PADDR excluding the byte align bits
        // If nextState is ERROR, drive prdata with Z
        end else begin
          apb.prdata = (nextState == ERROR) ? 'bz : reg_mem[apb.paddr[ADDR_WIDTH-1:ALIGNBITS]];
        end

        // Note: to simulate waitstates,
        // PREADY needs to be deasserted (maybe use
        // a counter to keep PREADY deasserted for
        // x number of cycles)
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
        // Check if device is selected and if the state is
        // not in a secondary or subsequent cycle of the APB transfer
        if (apb.psel) begin
          nextState = SETUP;

        // Else remain in IDLE mode
        end else begin
          nextState = IDLE;
        end
      end
      // SETUP: a transfer has been sent by REQUESTER
      SETUP: begin
        // If the requester is ready for access and therr,
        // are no more wait states the peripheral will 
        // transition to ACCESS
        if (wsCount == 0) begin
          nextState = ACCESS;
        end else begin
          nextState = SETUP;
        end
        // Checks for the following errors:
        // - If PSEL signal drops during SETUP
        // - If PADDR is not aligned
        // - If PENABLE signal is not asserted during SETUP
        // - If PPROT does not match the PPROT given by PADDR
        if (!apb.psel || !validAlign(apb.paddr) || !apb.penable || getPprot(apb.paddr) !== apb.pprot)
          nextState = ERROR;     // Go to ERROR state
      end
      // ACCESS: checks for continued chained accesses
      ACCESS: begin
          // If PSEL still is high, go back to SETUP
          // for chained reads/writes
          if (apb.psel) begin
            nextState = SETUP;

          // Else return back to IDLE
          end else begin
            nextState = IDLE;
          end
        end
        // ERROR: alt. state for ACCESS when illegal action
        // is detected by COMPLETER
      ERROR: begin
          nextState = IDLE;
      end
    endcase
  end

endmodule
