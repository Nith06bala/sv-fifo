`include "uvm_macros.svh"
import uvm_pkg::*;


// Interface

interface fifo_if (input logic clk);
  logic       rst;
  logic [7:0] in, out;
  logic       wren, rden, empty, full;

  clocking drv_cb @(posedge clk);
    default input #1ns output #1ns;
    output rst;
    output in;
    output wren;
    output rden;
    input  full;
    input  empty;
    input  out;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1ns output #1ns;
    input rst;
    input in;
    input wren;
    input rden;
    input full;
    input empty;
    input out;
  endclocking
endinterface

class fifo_seq_item extends uvm_sequence_item;
  `uvm_object_utils(fifo_seq_item)

  rand bit [7:0] in;
    logic [7:0] out;
  logic       wren, rden, full, empty;
  logic rst;

  function new(string name = "fifo_seq_item");
    super.new(name);
  endfunction
endclass


class fifo_random_seq extends uvm_sequence #(fifo_seq_item);
  `uvm_object_utils(fifo_random_seq)

  function new(string name = "fifo_random_seq");
    super.new(name);
  endfunction

  virtual task body();
    repeat (1) begin
      req = fifo_seq_item::type_id::create("req");
      start_item(req);
      if (!req.randomize())
        `uvm_error("SEQ", "Randomization failed")
      finish_item(req);
    end
  endtask
endclass


// Driver

class fifo_driver extends uvm_driver #(fifo_seq_item);
  `uvm_component_utils(fifo_driver)

  virtual fifo_if vif;

  function new(string name = "fifo_driver", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual fifo_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "Could not get vif")
  endfunction

  virtual task run_phase(uvm_phase phase);
    vif.drv_cb.rst <= 1;
    vif.drv_cb.wren  <= 0;
    vif.drv_cb.rden  <= 0;
    vif.drv_cb.in    <= '0;
    repeat (3) @(vif.drv_cb);
    vif.drv_cb.rst <= 1;
    @(vif.drv_cb);

    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  task drive_item(fifo_seq_item item);
    int i;
    for(i=0;i<20;i++)begin
      if(i>=0 && i<=7)begin
      @(vif.drv_cb);
       vif.drv_cb.rst <= 0;
      vif.drv_cb.wren <= 1;
      vif.drv_cb.rden <= 0;
      vif.drv_cb.in   <= item.in;
    end

     else if(i==8)begin
    @(vif.drv_cb);
    vif.drv_cb.wren <= 1;
    vif.drv_cb.rden <= 0;
    vif.drv_cb.in   <= item.in;
      end

      else if(i>=9 && i<=16)begin
      @(vif.drv_cb);
      vif.drv_cb.wren <= 0;
      vif.drv_cb.rden <= 1;
    end
    else if(i==17)begin
    @(vif.drv_cb);
    vif.drv_cb.wren <= 0;
    vif.drv_cb.rden <= 1;
    end
    else if(i>=18 && i<=19)begin
      @(vif.drv_cb);
      vif.drv_cb.wren <= 1;
      vif.drv_cb.rden <= 1;
      vif.drv_cb.in   <= item.in;
    end
   else begin
    @(vif.drv_cb);
    vif.drv_cb.wren <= 0;
    vif.drv_cb.rden <= 0;
   end
    end
  endtask
endclass


// Monitor

class fifo_monitor extends uvm_monitor;
  `uvm_component_utils(fifo_monitor)

  virtual fifo_if               vif;
  uvm_analysis_port #(fifo_seq_item) item_collected_port;

  function new(string name = "fifo_monitor", uvm_component parent);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual fifo_if)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "Could not get vif")
  endfunction

  virtual task run_phase(uvm_phase phase);
    fifo_seq_item item;
    forever begin
      @(vif.mon_cb);
      item         = fifo_seq_item::type_id::create("item");
      item.in      = vif.mon_cb.in;
      item.wren    = vif.mon_cb.wren;
      item.rden    = vif.mon_cb.rden;
      item.out     = vif.mon_cb.out;
      item.full    = vif.mon_cb.full;
      item.empty   = vif.mon_cb.empty;
      item.rst =  vif.mon_cb.rst;
      item_collected_port.write(item);
    end
  endtask
endclass


// Agent

class fifo_agent extends uvm_agent;
  `uvm_component_utils(fifo_agent)

  uvm_sequencer #(fifo_seq_item) seqr;
  fifo_driver                    drv;
  fifo_monitor                   mon;

  function new(string name = "fifo_agent", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    seqr = uvm_sequencer #(fifo_seq_item)::type_id::create("seqr", this);
    drv  = fifo_driver::type_id::create("drv", this);
    mon  = fifo_monitor::type_id::create("mon", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass


class fifo_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(fifo_scoreboard)

  uvm_analysis_imp #(fifo_seq_item, fifo_scoreboard) mon_export;

  int unsigned write_count   = 0;
  int unsigned read_count    = 0;
  bit          expected_full  = 1'b0;
  bit          expected_empty = 1'b1;  // starts empty after reset
  int pass_count=0;
  int fail_count=0;
  int wrap_rd=0;
  int wrap_wr=0;

  function new(string name = "fifo_scoreboard", uvm_component parent);
    super.new(name, parent);
    mon_export = new("mon_export", this);
  endfunction

  virtual function void write(fifo_seq_item item);

    if ( (! $isunknown({item.rst, item.full, item.empty})) && ((item.full  !== expected_full) ||
         (item.empty !== expected_empty))) begin // here this ! $unknown prevents checking for first state 
      `uvm_error("SCB_FAIL",
                 $sformatf("MISMATCH: wren=%0b rden=%0b write_count=%0d read_count=%0d rst=%0b| DUT full=%0b empty=%0b | EXP full=%0b empty=%0b",
          item.wren, item.rden, write_count,read_count,
          item.full,  item.empty,item.rst,
          expected_full, expected_empty))
      fail_count++;
    end 
    
    else if ($isunknown({item.rst, item.full, item.empty})) begin
    `uvm_info("SCB",
              "Ignoring uninitialized FIFO state before reset",
              UVM_LOW)
    //return;
        pass_count++;
end
    else  begin
      `uvm_info("SCB_PASS",
                $sformatf("OK : wren=%0b rden=%0b write_count=%0d read_count=%0d full=%0b empty=%0b rst=%0b",
          item.wren, item.rden, write_count,read_count,
                  item.full, item.empty,item.rst),UVM_LOW)
      pass_count++;
    end

    if(item.wren==1'b1 && expected_full==1'b0)begin
      if(write_count==3'd7)begin
        write_count = 0;
        wrap_wr = ~wrap_wr;
      end
      else begin
        write_count = write_count + 1;
      end
    end

    if(item.rden==1'b1 && expected_empty==1'b0)begin
      if(read_count==3'd7)begin
        read_count = 0;
        wrap_rd = ~wrap_rd;
      end
      else begin
        read_count = read_count + 1;
      end
    end

    if(read_count==write_count)begin
      expected_empty = ~(wrap_wr ^ wrap_rd);
      expected_full  =  (wrap_rd ^ wrap_wr);
    end
    else begin
      expected_full  = 1'b0;
      expected_empty = 1'b0;
    end
     endfunction

  virtual function void report_phase(uvm_phase phase);
    `uvm_info("SCB_SUMMARY",
      $sformatf("=== Scoreboard done  PASS: %0d   FAIL: %0d ===",
        pass_count, fail_count), UVM_NONE)
  endfunction
endclass



// Environment

class fifo_env extends uvm_env;
  `uvm_component_utils(fifo_env)

  fifo_agent      agt;
  fifo_scoreboard scb;

  function new(string name = "fifo_env", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agt = fifo_agent::type_id::create("agt", this);
    scb = fifo_scoreboard::type_id::create("scb", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    agt.mon.item_collected_port.connect(scb.mon_export);
  endfunction
endclass


// Test

class fifo_test extends uvm_test;
  `uvm_component_utils(fifo_test)

  fifo_env env;

  function new(string name = "fifo_test", uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = fifo_env::type_id::create("env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    fifo_random_seq rand_seq;
    rand_seq = fifo_random_seq::type_id::create("rand_seq");
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting FIFO sequences", UVM_LOW)
    rand_seq.start(env.agt.seqr);
    #50ns;
    phase.drop_objection(this);
  endtask
endclass


// Top-module

module tb_top;
  bit clk;
  always #5ns clk = ~clk;

  fifo_if inf (.clk(clk));


  fifo dut (
    .clk   (inf.clk),
    .rst   (inf.rst),
    .in    (inf.in),
    .out   (inf.out),
    .wren  (inf.wren),
    .rden  (inf.rden),
    .empty (inf.empty),
    .full  (inf.full)
  );

  initial begin
    uvm_config_db #(virtual fifo_if)::set(null, "*", "vif", inf);
    run_test("fifo_test");
  end
endmodule
