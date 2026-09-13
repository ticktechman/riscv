/* linker.ld */
OUTPUT_ARCH("riscv")
ENTRY(_start)

PHDRS
{
  text_phdr PT_LOAD FLAGS(5);   /* 5 = R + X */
  rodata_phdr PT_LOAD FLAGS(4); /* 4 = R */
  rwdata_phdr PT_LOAD FLAGS(6); /* 6 = R + W */
}

SECTIONS
{
  /* 假设 BootROM 起始地址为 0x10000000 */
  . = 0x80000000;

  .text.init : {
    *(.text)
  } : text_phdr

  . = ALIGN(0x1000);
  .tohost : {
    QUAD(0);
    QUAD(0);
  } : rwdata_phdr

  . = ALIGN(0x1000);
  .rodata : {
    . = ALIGN(8);
    *(.rodata)
    *(.rodata.*)
  } : rodata_phdr

  /DISCARD/ : { *(.comment) *(.note*) }
}
