#include <cstdio>

#include "Vtop.h"
#include "verilated.h"

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  Vtop *top = new Vtop;

  top->rst_n = 0;
  top->clk = 0;

  printf("==> sim started.\n");
  for (int i = 0; !Verilated::gotFinish(); i++) {
    top->rst_n = i > 2 ? 1 : 0;
    top->clk = !top->clk;
    top->eval();
  }

  delete top;
  printf("==> sim exit.\n");
  return 0;
}
