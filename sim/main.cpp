#include "Vtop.h"
#include "verilated.h"
#include <cstdio>
#include <memory> // 建议使用智能指针

int main(int argc, char **argv) {
  const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
  contextp->commandArgs(argc, argv);

  Vtop *top = new Vtop{contextp.get()};

  top->rst_n = 0;
  top->clk = 0;

  printf("==> sim started.\n");
  for (int i = 0; !contextp->gotFinish(); i++) {
    contextp->timeInc(1);
    top->rst_n = i > 2 ? 1 : 0;
    top->clk = !top->clk;
    top->eval();
  }

  delete top;
  printf("==> sim exit. %llu\n", contextp->time());
  return 0;
}
