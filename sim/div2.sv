/*
 *******************************************************************************
 *
 *        filename: mini.sv
 *     description: mini verilog.
 *         created: 2026-05-01
 *          author: ticktechman
 *
 *******************************************************************************
 */

// build:  verilator -j 0 --timing --binary --trace -o mini --top-module top mini.sv && ./obj_dir/mini

`timescale 1ns / 100ps

`define LOGI(msg) $display("[I|%9t|%m] %s", $realtime, msg)
`define LOGW(msg) $display("[W|%9t|%m] %s", $realtime, msg)
`define LOGE(msg) $display("[E|%9t|%m] %s", $realtime, msg)

//-------------------------------------
// Testbench
//-------------------------------------
module top ();
  logic clk, rst_n;

  initial begin
    $dumpfile("mini.vcd");
    $dumpvars(0, top);
    $timeformat(-9, 3, "", 9);
  end

  clkgen clock (
    .clk(clk),
    .rst_n(rst_n)
  );

  mini m1 (
    .clk(clk),
    .rst_n(rst_n)
  );

endmodule

//-------------------------------------
// clock gen
//-------------------------------------
module clkgen #(
  parameter COUNTER = 18
) (
  output logic clk,
  output logic rst_n
);
  initial begin
    clk   = 0;
    rst_n = 0;
    #1.5 rst_n = 1;
    repeat (COUNTER) @(negedge clk);
    #0.5 rst_n = 0;
    #0.1 $finish;
  end

  always #1 clk = ~clk;
endmodule

//-------------------------------------
// clock gen
//-------------------------------------
module mini (
  input logic clk,
  input logic rst_n
);

  typedef enum {
    idle,
    div,
    done
  } state_e;

  logic [7:0] divident, divisor, quotient, reminder;
  logic [16:0] holder, holder_r;
  int counter, counter_r;

  state_e state, state_r;
  logic [8:0] sub;
  assign sub = holder_r[16:8] - {1'b0, divisor};

  always_comb begin
    divident = 8'd11;
    divisor  = 8'd3;
  end

  always_comb begin
    state = state_r;

    unique case (state)
      idle: begin
        `LOGI("idle");
        holder  = {9'b0, divident[3:0], 4'b0};
        counter = '0;
        state   = div;
      end
      div: begin

        if (!sub[8]) begin
          holder = {sub[7:0], holder_r[7:0], 1'b1};
        end else begin
          holder = {holder_r[15:0], 1'b0};
        end

        `LOGI($sformatf("rnd:%0d sub(%b) =>%b %b", counter_r, sub, holder[15:8], holder[7:0]));
        counter = counter_r + 32'd1;
        if (counter >= 4) begin
          state = done;
        end
      end
      done: begin
        quotient = !sub[8] ? {holder_r[6:0], 1'b1} : {holder_r[6:0], 1'b0};
        reminder = !sub[8] ? sub[7:0] : holder_r[15:8];
        `LOGI($sformatf("quotient:%0d reminder:%0d", quotient, reminder));
      end
      default: ;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      `LOGW("reset");
      state_r <= idle;
    end else begin
      `LOGI("hello");
      state_r   <= state;
      counter_r <= counter;
      holder_r  <= holder;
    end
  end

endmodule

/******************************************************************************/
