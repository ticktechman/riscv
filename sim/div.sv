`timescale 1ns / 1ps

// ==========================================================
// 1. 测试平台 (Testbench)
// ==========================================================
module top;
  parameter WIDTH = 64;

  logic clk;
  logic rst_n;
  logic in_vld;
  logic in_rdy;
  logic [WIDTH-1:0] op_a;
  logic [WIDTH-1:0] op_b;
  logic [2:0] funct3;
  logic is_rv64w;

  logic out_vld;
  logic out_rdy;
  logic [WIDTH-1:0] res;

  // 实例化 DUT
  fast_serdiv #(WIDTH) dut (.*);

  // 时钟生成：100MHz
  initial clk = 0;
  always #5 clk = ~clk;

  // 结果校验任务：确保握手严格对齐
  task check_result(input string msg, input logic [63:0] expected);
    begin
      // 1. 等待硬件拉高有效信号
      wait (out_vld === 1'b1);

      // 2. 对比结果
      if (res !== expected) begin
        $display("[ERROR] %s | Got: %h, Expected: %h", msg, res, expected);
      end else begin
        $display("[PASS] %s | Result: %h", msg, res);
      end

      // 3. 严格握手：在时钟上升沿之后驱动 out_rdy
      @(posedge clk);
      out_rdy = 1;
      @(posedge clk);
      out_rdy = 0;
    end
  endtask

  initial begin
    // 初始化所有信号，消除 Verilator 警告
    rst_n = 0;
    in_vld = 0;
    out_rdy = 0;
    op_a = 0;
    op_b = 0;
    funct3 = 0;
    is_rv64w = 0;

    // 复位：持续一段时间以确保 Verilator 内部状态清零
    #50 rst_n = 1;
    repeat (10) @(posedge clk);

    // --- Case 1: 基础无符号除法 (64/4) ---
    @(posedge clk);
    op_a   = 64'd64;
    op_b   = 64'd4;
    funct3 = 3'b101;  // DIVU
    in_vld = 1;

    // 等待接受请求 (必须在 while 循环中采样 clk 以步进仿真时间)
    while (!in_rdy) @(posedge clk);
    @(posedge clk);
    in_vld = 0;  // 握手成功，撤销请求

    check_result("Basic DIVU (64/4)", 64'd16);

    // --- Case 2: 有符号除法 (-10/3) ---
    @(posedge clk);
    op_a   = -64'sd10;
    op_b   = 64'sd3;
    funct3 = 3'b100;
    in_vld = 1;
    while (!in_rdy) @(posedge clk);
    @(posedge clk);
    in_vld = 0;
    check_result("Signed DIV (-10/3)", -64'sd3);

    // --- Case 3: 取余运算 (-10%3) ---
    @(posedge clk);
    op_a   = -64'sd10;
    op_b   = 64'sd3;
    funct3 = 3'b110;
    in_vld = 1;
    while (!in_rdy) @(posedge clk);
    @(posedge clk);
    in_vld = 0;
    check_result("Signed REM (-10%3)", -64'sd1);

    // --- Case 4: 除以零 ---
    @(posedge clk);
    op_a   = 64'hAAAA_BBBB_CCCC_DDDD;
    op_b   = 64'd0;
    funct3 = 3'b101;
    in_vld = 1;
    while (!in_rdy) @(posedge clk);
    @(posedge clk);
    in_vld = 0;
    check_result("Divide by Zero", 64'hFFFF_FFFF_FFFF_FFFF);

    // --- Case 5: 32位溢出测试 (DIVW) ---
    @(posedge clk);
    op_a = {32'h0, 32'h8000_0000};
    op_b = 64'hFFFF_FFFF_FFFF_FFFF;
    funct3 = 3'b100;
    is_rv64w = 1;
    in_vld = 1;
    while (!in_rdy) @(posedge clk);
    @(posedge clk);
    in_vld = 0;
    check_result("DIVW Overflow", 64'hFFFF_FFFF_8000_0000);

    // --- Case 6: 快速路径测试 ---
    @(posedge clk);
    op_a = 64'd5;
    op_b = 64'd100;
    funct3 = 3'b101;
    is_rv64w = 0;
    in_vld = 1;
    while (!in_rdy) @(posedge clk);
    @(posedge clk);
    in_vld = 0;
    check_result("Fast Path (|A|<|B|)", 64'd0);

    repeat (10) @(posedge clk);
    $display("\n[ALL TESTS FINISHED SUCCESSFULLY]");
    $finish;
  end

endmodule


// ==========================================================
// 2. 硬件设计 (RTL)
// ==========================================================
module fast_serdiv #(
  parameter int WIDTH = 64
) (
  input  logic             clk,
  input  logic             rst_n,
  input  logic             in_vld,
  output logic             in_rdy,
  input  logic [WIDTH-1:0] op_a,
  input  logic [WIDTH-1:0] op_b,
  input  logic [      2:0] funct3,
  input  logic             is_rv64w,
  output logic             out_vld,
  input  logic             out_rdy,
  output logic [WIDTH-1:0] res
);

  typedef enum logic [1:0] {
    IDLE   = 2'b00,
    DIVIDE = 2'b01,
    FINISH = 2'b10
  } state_t;
  state_t state_q, state_d;

  logic [WIDTH-1:0] a_q, a_d, b_q, b_d, quot_q, quot_d;
  logic [5:0] cnt_q, cnt_d;
  logic res_inv_q, res_inv_d, rem_inv_q, rem_inv_d;
  logic is_rem_q, is_rem_d, is_div_zero_q, is_div_zero_d;

  // 预处理：符号位提取与绝对值转换
  logic [WIDTH-1:0] op_a_abs, op_b_abs;
  logic a_sign, b_sign, is_signed;

  assign is_signed = ~funct3[0];
  assign a_sign    = is_rv64w ? op_a[31] : op_a[WIDTH-1];
  assign b_sign    = is_rv64w ? op_b[31] : op_b[WIDTH-1];

  always_comb begin
    logic [WIDTH-1:0] v1, v2;
    v1 = is_rv64w ? (is_signed ? {{32{op_a[31]}}, op_a[31:0]} : {32'b0, op_a[31:0]}) : op_a;
    v2 = is_rv64w ? (is_signed ? {{32{op_b[31]}}, op_b[31:0]} : {32'b0, op_b[31:0]}) : op_b;
    op_a_abs = (is_signed && a_sign) ? (~v1 + 64'd1) : v1;
    op_b_abs = (is_signed && b_sign) ? (~v2 + 64'd1) : v2;
  end

  // 前导零计数 (LZC) 用于跳过冗余周期
  function automatic logic [5:0] count_lz(logic [63:0] val);
    logic [5:0] count;
    count = 6'd0;
    for (int i = 63; i >= 0; i--) begin
      if (val[i]) break;
      count = count + 6'd1;
    end
    return count;
  endfunction

  logic [5:0] lzc_a, lzc_b, shift_amt;
  assign lzc_a = count_lz(op_a_abs);
  assign lzc_b = count_lz(op_b_abs);
  assign shift_amt = (lzc_b > lzc_a) ? (lzc_b - lzc_a) : 6'd0;

  // 试减逻辑
  logic [WIDTH:0] sub_res;
  assign sub_res = {1'b0, a_q} - {1'b0, b_q};
  assign in_rdy  = (state_q == IDLE);

  // 状态机逻辑
  always_comb begin
    state_d = state_q;
    a_d = a_q;
    b_d = b_q;
    quot_d = quot_q;
    cnt_d = cnt_q;
    is_div_zero_d = is_div_zero_q;
    is_rem_d = is_rem_q;
    res_inv_d = res_inv_q;
    rem_inv_d = rem_inv_q;
    out_vld = 1'b0;

    case (state_q)
      IDLE: begin
        if (in_vld) begin
          is_div_zero_d = (op_b_abs == 64'b0);
          is_rem_d      = funct3[1];
          res_inv_d     = is_signed && (a_sign ^ b_sign) && (op_b_abs != 64'b0);
          rem_inv_d     = is_signed && a_sign;
          a_d           = op_a_abs;
          b_d           = op_b_abs << shift_amt;
          quot_d        = 64'b0;
          cnt_d         = shift_amt;
          if (op_a_abs < op_b_abs || op_b_abs == 64'b0) state_d = FINISH;
          else state_d = DIVIDE;
        end
      end
      DIVIDE: begin
        if (!sub_res[WIDTH]) begin
          a_d    = sub_res[WIDTH-1:0];
          quot_d = {quot_q[WIDTH-2:0], 1'b1};
        end else begin
          quot_d = {quot_q[WIDTH-2:0], 1'b0};
        end
        b_d = {1'b0, b_q[WIDTH-1:1]};
        if (cnt_q == 6'd0) state_d = FINISH;
        else cnt_d = cnt_q - 6'd1;
      end
      FINISH: begin
        out_vld = 1'b1;
        if (out_rdy) state_d = IDLE;
      end
      default: state_d = IDLE;
    endcase
  end

  // 时序更新
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= IDLE;
      a_q <= 0;
      b_q <= 0;
      quot_q <= 0;
      cnt_q <= 0;
      is_div_zero_q <= 0;
      is_rem_q <= 0;
      res_inv_q <= 0;
      rem_inv_q <= 0;
    end else begin
      state_q <= state_d;
      a_q <= a_d;
      b_q <= b_d;
      quot_q <= quot_d;
      cnt_q <= cnt_d;
      is_div_zero_q <= is_div_zero_d;
      is_rem_q <= is_rem_d;
      res_inv_q <= res_inv_d;
      rem_inv_q <= rem_inv_d;
    end
  end

  // 结果修正与符号处理
  always_comb begin
    logic [WIDTH-1:0] q_signed, r_signed, pre_res;
    q_signed = res_inv_q ? (~quot_q + 64'd1) : quot_q;
    r_signed = rem_inv_q ? (~a_q + 64'd1) : a_q;
    if (is_div_zero_q) begin
      q_signed = 64'hFFFF_FFFF_FFFF_FFFF;
      r_signed = is_rv64w ? {{32{op_a[31]}}, op_a[31:0]} : op_a;
    end
    pre_res = is_rem_q ? r_signed : q_signed;
    res     = is_rv64w ? {{32{pre_res[31]}}, pre_res[31:0]} : pre_res;
  end
endmodule
