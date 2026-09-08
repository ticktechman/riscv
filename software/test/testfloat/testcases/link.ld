/* linker.ld */
OUTPUT_ARCH("riscv")
ENTRY(_start)

PHDRS
{
  text_phdr PT_LOAD FLAGS(5);   /* 5 = R + X */
  data_phdr PT_LOAD FLAGS(4); /* 6 = R + W */
}

SECTIONS
{
  /* 假设 BootROM 起始地址为 0x10000000 */
  . = 0x80000000;
  .text.init : {
    *(.text.init)
  } : text_phdr

  . = 0x80001000;
  .tohost : { *(.tohost) }

  . = 0x80002000;
  .data : {
    . = ALIGN(8);
    *(.data)
    *(.data.*)
  } : data_phdr

  /DISCARD/ : { *(.comment) *(.note*) }
}
