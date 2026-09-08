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

`define LOGI(msg) $display("[I|%9t|%m.%0d] %s", $realtime, `__LINE__, msg)
`define LOGW(msg) $display("[W|%9t|%m.%0d] %s", $realtime, `__LINE__, msg)
`define LOGE(msg) $display("[E|%9t|%m.%0d] %s", $realtime, `__LINE__, msg)

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
  parameter COUNTER = 100
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
    IDLE,
    PREPARE,
    ITER,
    ROUND,
    DONE
  } state_e;

  typedef struct packed {logic G, R, S, L;} grs_t;

  typedef logic [63:0] reg_t;
  localparam BP = 64;
  localparam MP = BP + 5;
  localparam N = 30;

  function automatic logic signed [MP-1:0] mul_s(logic [2:0] s, logic signed [MP-1:0] f);
    unique case (s)
      3'sd0:   return MP'(0);
      3'sd1:   return f;
      3'sd2:   return f <<< 1;
      -3'sd1:  return (~f) + MP'(1);
      -3'sd2:  return (~(f <<< 1) + MP'(1));
      default: return MP'(0);
    endcase
  endfunction

  function automatic logic [2:0] select_s(logic signed [MP-1:0] fr4, logic signed [MP-1:0] partial_s, int shift);
    localparam BITS = 12;
    logic signed [2:0] candidates[3];
    logic signed [2:0] fit;
    logic signed [MP-1:0] new_s;
    logic signed [MP-1:0] v1, v2, delta, best_delta;

    if (partial_s == MP'(0)) begin
      return 3'd0;
    end

    if (fr4 >= MP'(0)) begin
      candidates = {3'sd0, 3'sd1, 3'sd2};
    end else begin
      candidates = {3'sd0, -3'sd1, -3'sd2};
    end

    best_delta = {1'b0, {(MP - 1) {1'b1}}};
    foreach (candidates[i]) begin
      if (shift >= 0) begin
        new_s = partial_s + (MP'(candidates[i]) <<< shift);
      end else begin
        new_s = partial_s;
      end

      v1 = fr4 >>> (BP - BITS);
      v2 = new_s >>> (BP - BITS);
      delta = v1 - mul_s(candidates[i], v2);
      if (delta < 0) begin
        delta = -delta;
      end
      if (best_delta > delta) begin
        best_delta = delta;
        fit = candidates[i];
      end
    end

    return fit;
  endfunction

  real val;
  reg_t x;
  always_comb begin
    val = 3.141592653589793;
    x   = $realtobits(val);
    `LOGI($sformatf("x=0x%h", x));
  end


  state_e state, next_state;
  int counter, max_count, sh;

  always_comb begin
    unique case (state)
      IDLE: next_state = PREPARE;
      PREPARE: next_state = ITER;
      ITER: next_state = counter >= max_count ? ROUND : ITER;
      ROUND: next_state = DONE;
      DONE: next_state = IDLE;
    endcase
  end

  logic G, R, Sticky, L, rnd;
  logic [51:0] manti;
  logic [10:0] final_e;
  reg_t result;
  always_comb begin
    logic signed [10:0] e;
    logic [52:0] m;
    logic signed [MP-1:0] rem, S, fr4, s2, new_s, inc, mq;
    logic signed [2:0] s;
    grs_t grs;
    unique case (state)
      IDLE: begin
        grs = '{default: 0};
      end
      PREPARE: begin
        e   = $signed(x[62:52]) - 11'sd1023;
        m   = {1'b1, x[51:0]};

        rem = MP'(m) <<< (BP - 52);
        S   = MP'(1) <<< BP;
        if (e[0]) begin
          rem = rem >>> 1;
          s   = x[51] == 1'b1 ? 3'sd0 : -3'sd1;
        end else begin
          rem = rem >>> 2;
          s   = x[51] == 1'b1 ? -3'sd1 : -3'sd2;
        end
        rem -= (MP'(1) <<< BP);

        S += (MP'(s) << (BP - 2));
        new_s = MP'(2 << BP) + MP'(s <<< (BP - 2));
        rem   = (rem <<< 2) - mul_s(s, new_s);

        `LOGI($sformatf("rem:%0d S:%0d", rem, S));
        counter   = 0;
        max_count = N;
        final_e   = '0;
      end
      ITER: begin
        counter = counter + 1;
        sh = BP - ((counter + 1) << 1);
        fr4 = rem <<< 2;
        s2 = S <<< 1;
        s = select_s(fr4, s2, sh);
        inc = (sh >= 0 ? MP'(s) <<< sh : '0);
        new_s = s2 + inc;
        rem = fr4 - mul_s(s, new_s);
        S = S + inc;
      end
      DONE: begin
        S = S <<< 1;
        mq = S - (1 << BP);
        grs.G = mq[BP-53];
        grs.R = mq[BP-54];
        grs.L = mq[BP-52];
        grs.S = |mq[BP-55:0];
        rnd = grs.G & (grs.L | grs.R | grs.S);

        manti = mq[BP-1:BP-52];
        if (rnd) begin
          manti = manti + 52'd1;
        end
        final_e = (e >>> 1) + 11'sd1023;
        // `LOGI($sformatf("e:%0d, manti:%h", final_e, manti));

        result  = {x[63], final_e, manti};
        `LOGI($sformatf("result:%.16f .vs. %.16f", $bitstoreal(result), $sqrt(val)));
        `LOGI("DONE.");
        $finish(0);
      end
      default: ;
    endcase
  end

  always_comb begin
    real r;
    real s;
    r = $bitstoreal(64'h7FEFFFFFFFFFFFFF);
    s = $sqrt(r);
    `LOGI($sformatf("==%h", $realtobits(s)));
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

endmodule

/******************************************************************************/
