/* linker.ld */
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  /* 假设 BootROM 起始地址为 0x10000000 */
  . = 0x00000000;

  .text : {
    *(.text)
  }

  .rodata : {
    . = ALIGN(8);
    *(.rodata)
    *(.rodata.*)
  }

  /DISCARD/ : { *(.comment) *(.note*) }
}
