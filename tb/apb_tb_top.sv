//////////////////////////////////////////////////////////////
// apb_tb_top.sv - Top level module for testing APB protocol
//
// Description:
// ------------
// Top level module which instantiates the interface, APB
// peripheral, and the APB bridge. Controls overall flow of
// testing by calling individual test function.
// Also generates the clock and reset signal.
////////////////////////////////////////////////////////////////

`include "../src/apb_pkg.sv"

module apb_tb_top;
  // Clock and Reset
  logic pclk = 0;
  logic presetn = 1;

  // Clock generation
  // 10ns period (100MHz clock)
  always #5 pclk = ~pclk;

  // Instantiate APB interface
  apb_if #(
    .ADDR_WIDTH(apb_pkg::ADDR_WIDTH),
    .DATA_WIDTH(apb_pkg::DATA_WIDTH),
    .STRB_WIDTH(apb_pkg::STRB_WIDTH)
  ) apb(
      pclk,
      presetn
  );

  // Instantiate APB Bridge
  apb_bridge bridge(apb.bridge);

  // Instantiate APB Peripheral
  apb_peripheral dut(apb.peripheral);

  initial begin
    $display("Starting APB Test...");
    // Reset with active-low signal, starting high since
    // the peripheral is looking for a negedge on this signal
    presetn = 1;
    pclk = 0;
    @(posedge pclk);
    presetn = 0;
    @(posedge pclk);
    // Reset complete
    presetn = 1;
    repeat (2) @(posedge pclk);
  end
endmodule
