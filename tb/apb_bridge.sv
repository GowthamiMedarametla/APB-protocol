//////////////////////////////////////////////////////////////
// apb_bridge.sv - APB Bridge, which serves as a testbench
//
// Description:
// ------------
// This module simulates the role of the APB requester by
// acting as an APB bridge. It initiates transfers such as
// reads and writes. The top module provides the pclk and
// presetn signals.
//
////////////////////////////////////////////////////////////////

module apb_bridge (
    apb_if.bridge apb
);

  import apb_pkg::*;

  logic [apb.ADDR_WIDTH-1:0] test_addr = {{(apb.ADDR_WIDTH - 4) {1'b0}}, 4'h4};
  logic [apb.DATA_WIDTH-1:0] read_data;
  logic [2:0] pprot;
  logic [2:0] pprot_bits_invert;
  logic [apb.ADDR_WIDTH-1:0] pprot_addr;

  // Main test sequence
  initial begin
    // Wait after reset before starting transactions
    repeat (4) @(posedge apb.pclk);
    $display("Performing APB Read Transaction...");

    //
    // Read transfer tests
    //
    // Get expected pprot bits based on the test_addr value
    pprot = getPprot(test_addr);
    // Test that a basic read from a reset state with correct pprot bits for the address
    // does not error and returns the data that was read
    test_read(.addr(test_addr), .pprot(pprot), .should_err(0), .reset(1), .data(read_data));
    $display("Read Data: %h", read_data);

    test_invalid_reads();

    //
    // Protection unit tests
    //
    // Use pprot_bits_invert to check the individual pprot bits, one position at a time
    pprot_bits_invert = 3'b001;
    // Modify existing test address to ensure it is valid for the specified pprot bits
    // We'll initially test all pprot bits being high
    pprot = 3'b111;
    pprot_addr = getAddrforPprot(pprot, test_addr);

    // First test the base case, where all high pprot bits should succeed for the calculated
    // pprot_addr based on the mapping logic from apb_pkg
    test_read(.addr(pprot_addr), .pprot(pprot), .should_err(0), .reset(1), .data(read_data));

    // Test pprot bit 0 (privileged region):
    // When bit is 0, fails for address in privileged region
    test_read(.addr(pprot_addr), .pprot(~pprot_bits_invert), .should_err(1), .reset(1),
              .data(read_data));

    // Test pprot bit 1 (secure region - bit is high for non-secure):
    pprot_bits_invert = pprot_bits_invert << 1'b1;
    // When bit is 0, fails for address in non-secure region
    test_read(.addr(pprot_addr), .pprot(~pprot_bits_invert), .should_err(1), .reset(1),
              .data(read_data));

    // Test pprot bit 2 (instruction region):
    pprot_bits_invert = pprot_bits_invert << 1'b1;
    // When bit is 0, fails for address in instruction region
    test_read(.addr(pprot_addr), .pprot(~pprot_bits_invert), .should_err(1), .reset(1),
              .data(read_data));

    // Wait a few cycles before finishing
    repeat (4) @(posedge apb.pclk);
    $finish;
  end

  // Task for performing an APB Read transaction
  task test_read(input logic [apb.ADDR_WIDTH-1:0] addr, input logic [2:0] pprot,
                 input logic should_err = 0, input logic reset = 1,
                 output logic [apb.DATA_WIDTH-1:0] data);
    // Counter for clock cycles waited
    automatic int wait_cycles = 0;
    // Allow caller to determine whether a reset is performed
    // here so that we can test sequential reads / writes without
    // a reset when needed.
    if (reset) reset_apb();

    begin
      //
      // Setup phase (1st clock cycle)
      //
      @(posedge apb.pclk);
      $display("Read Start: %0t", $time);
      apb.psel    = 1;
      apb.pprot   = pprot;
      apb.pwrite  = 0;
      // Ensure 4-byte alignment
      apb.paddr   = addr & ~(32'h3);
      apb.penable = 0;

      //
      // Access phase (2nd clock cycle)
      //
      @(posedge apb.pclk);
      apb.penable = 1;

      // Wait for `pready` while counting cycles
      wait_cycles = 0;
      while (!apb.pready) begin
        @(posedge apb.pclk);
        wait_cycles++;
      end
      // Then read the data
      data = apb.prdata;

      // Check that the peripheral error was present when an error is expected,
      // or not present when it should not be
      if (should_err)
        assert (apb.pslverr)
        else
          $error("APB Read test FAILED: Peripheral error not detected when it should have been.");
      else
        assert (!apb.pslverr)
        else $error("APB Read test FAILED: Unexpected peripheral error.");


      // Deassert signals
      apb.psel    = 0;
      apb.penable = 0;
      
      $display("(%0t) APB Read completed in %0d cycles.", $time, wait_cycles);
    end
  endtask

  task test_invalid_reads();
    logic [apb.DATA_WIDTH-1:0] data;

    // Test Case 1: Deassert PSEL too early
    begin
      reset_apb();
      $display("Starting Invalid Read Test: Early PSEL deassertion...");
      @(posedge apb.pclk);
      $display("Read Start: %0t", $time);
      apb.psel    = 1;
      apb.pprot   = '0;
      apb.pwrite  = 0;
      apb.paddr   = 32'h4;
      apb.penable = 0;

      @(posedge apb.pclk);
      apb.penable = 1;

      //
      // **Break the protocol: Deassert PSEL early**
      //
      apb.psel = 0;

      // Wait for PREADY and check PSLVERR
      @(posedge apb.pclk);
      wait (apb.pready);
      assert (apb.pslverr)
      else $error("APB Invalid Read Test (Early PSEL Deassertion) FAILED: PSLVERR not asserted.");

      @(posedge apb.pclk);
      apb.penable = 0;
      @(posedge apb.pclk);
    end

    // Test Case 2: Unaligned Address
    begin
      reset_apb();
      $display("Starting Invalid Read Test: Unaligned Address...");
      @(posedge apb.pclk);
      $display("Read Start: %0t", $time);
      apb.psel    = 1;
      apb.pwrite  = 0;
      //
      // **Intentionally misaligned**
      //
      apb.paddr   = 32'h3;
      apb.penable = 0;

      @(posedge apb.pclk);
      apb.penable = 1;

      // Wait for PREADY and check PSLVERR
      @(posedge apb.pclk);
      wait (apb.pready);
      assert (apb.pslverr)
      else $error("APB Invalid Read Test (Unaligned Address) FAILED: PSLVERR not asserted.");

      @(posedge apb.pclk);
      apb.psel    = 0;
      apb.penable = 0;
      @(posedge apb.pclk);
    end

    $display("Invalid Read Test Completed.");
  endtask


  task reset_apb();
    // Ensure all signals start with known values
    apb.psel    = 0;
    apb.penable = 0;
    apb.pprot   = '0;
    apb.pwrite  = 0;
    apb.paddr   = 0;
    apb.pwdata  = 0;
    apb.pstrb   = 0;

    // Wait one clock cycle for values to settle
    @(posedge apb.pclk);
  endtask
endmodule
