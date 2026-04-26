#include "Vtop.h"
#include "verilated.h"
#include "verilated_vcd_c.h" // 1. 引入 VCD 追踪头文件

int main(int argc, char **argv) {
  const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
  contextp->commandArgs(argc, argv);

  // 2. 开启追踪上下文 (必须在 new Vtop 之前调用)
  contextp->traceEverOn(true);

  Vtop *top = new Vtop{contextp.get()};

  // 3. 实例化 VCD 追踪对象
  std::unique_ptr<VerilatedVcdC> tfp{new VerilatedVcdC};

  // 4. 将 top 模块连接到追踪对象 (层级设为 99 表示追踪所有信号)
  top->trace(tfp.get(), 99);

  // 5. 打开输出文件 (例如 sim.vcd)
  tfp->open("sim.vcd");

  top->rst_n = 0;
  top->clk = 0;

  printf("==> sim started.\n");

  for (int i = 0; !contextp->gotFinish(); i++) {
    contextp->timeInc(1);
    top->rst_n = i > 2 ? 1 : 0;
    top->clk = !top->clk;

    top->eval(); // 评估逻辑

    tfp->dump(contextp->time()); // 6. 将当前时刻的信号值写入 VCD 文件
  }

  // 7. 仿真结束后的清理工作
  tfp->close(); // 关闭 VCD 文件
  delete top;
  printf("==> sim exit @ %llu\n", contextp->time());
  return 0;
}
