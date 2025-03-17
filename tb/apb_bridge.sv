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

    // Read transfer tests
    pprot = getPprot(test_addr);
    test_read(.addr(test_addr), .pprot(pprot), .should_err(0), .reset(1), .data(read_data));
    $display("Read Data: %h", read_data);

    test_invalid_reads();

    // Protection unit tests
    pprot_bits_invert = 3'b001;
    pprot = 3'b111;
    pprot_addr = getAddrforPprot(pprot, test_addr);
    test_read(.addr(pprot_addr), .pprot(pprot), .should_err(0), .reset(1), .data(read_data));

    pprot_bits_invert = pprot_bits_invert << 1'b1;
    test_read(.addr(pprot_addr), .pprot(~pprot_bits_invert), .should_err(1), .reset(1), .data(read_data));

    pprot_bits_invert = pprot_bits_invert << 1'b1;
    test_read(.addr(pprot_addr), .pprot(~pprot_bits_invert), .should_err(1), .reset(1), .data(read_data));

    repeat (4) @(posedge apb.pclk);
    $finish;
  end

  task test_read(input logic [apb.ADDR_WIDTH-1:0] addr, input logic [2:0] pprot,
                 input logic should_err = 0, input logic reset = 1,
                 output logic [apb.DATA_WIDTH-1:0] data);
    automatic int wait_cycles = 0;
    if (reset) reset_apb();

    begin
      @(posedge apb.pclk);
      $display("Read Start: %0t", $time);
      apb.psel    = 1;
      apb.pprot   = pprot;
      apb.pwrite  = 0;
      apb.paddr   = addr & ~(32'h3);
      apb.penable = 0;

      @(posedge apb.pclk);
      apb.penable = 1;

      wait_cycles = 0;
      while (!apb.pready) begin
        @(posedge apb.pclk);
        wait_cycles++;
      end
      data = apb.prdata;

      if (should_err)
        assert (apb.pslverr)
        else
          $error("APB Read test FAILED: Peripheral error not detected when it should have been.");
      else
        assert (!apb.pslverr)
        else $error("APB Read test FAILED: Unexpected peripheral error.");

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

      apb.psel = 0;

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
      apb.paddr   = 32'h3;
      apb.penable = 0;

      @(posedge apb.pclk);
      apb.penable = 1;

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
    apb.psel    = 0;
    apb.penable = 0;
    apb.pprot   = '0;
    apb.pwrite  = 0;
    apb.paddr   = 0;
    apb.prdata  = '0;
  endtask
endmodule
